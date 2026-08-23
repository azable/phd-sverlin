{-# LANGUAGE OverloadedStrings #-}

-- | Small, permissively authored syntax set interpreted by skylighting-core.
-- The project deliberately does not bundle KDE's GPL XML grammar corpus.
module LinearTrace.Visualization.CodeHighlight
  ( highlightCodeLines
  , supportedCodeLanguages
  ) where

import qualified Data.ByteString              as BS
import qualified Data.Char                    as Char
import qualified Data.Map.Strict              as Map
import qualified Data.Maybe                   as Maybe
import qualified Data.Text                    as Text
import qualified Data.Text.Encoding           as TextEncoding
import qualified Data.Text.Lazy               as LazyText
import qualified LinearTrace.Visualization.IR as IR
import           Prelude
import qualified Skylighting.Core             as Sky

data LanguageDefinition = LanguageDefinition
  { languageName          :: String
  , languageKeywords      :: [String]
  , languageLineComments  :: [(Char, Maybe Char)]
  , languageBlockComments :: [((Char, Char), (Char, Char))]
  }

supportedCodeLanguages :: [String]
supportedCodeLanguages = Map.keys languageDefinitions

highlightCodeLines ::
     String
  -> String
  -> [(IR.TextSourceRange, String)]
  -> Either String [IR.CodeHighlightLine]
highlightCodeLines requested source lines' = do
  definition <-
    maybe
      (Left
         ("unsupported code highlighting language "
            ++ show requested
            ++ "; expected one of "
            ++ show supportedCodeLanguages))
      Right
      (Map.lookup (normalize requested) languageDefinitions)
  syntax <-
    Sky.parseSyntaxDefinitionFromText
      (normalize requested ++ ".xml")
      (LazyText.pack (syntaxXml definition))
  tokenLines <-
    Sky.tokenize
      Sky.TokenizerConfig
        { Sky.syntaxMap = Map.singleton (Sky.sName syntax) syntax
        , Sky.traceOutput = False
        }
      syntax
      (Text.pack source)
  let sourceLines = physicalLines source
      sourceTokens =
        concat
          (zipWith
             materializeSourceLine
             sourceLines
             (padTo (length sourceLines) tokenLines))
  traverse (projectLine sourceTokens) lines'
  where
    materializeSourceLine (lineStart, _display) tokens =
      snd (foldl materializeToken (lineStart, []) tokens)
    materializeToken (offset, result) (kind, tokenText) =
      let value = Text.unpack tokenText
          nextOffset = offset + utf8Length value
          token =
            IR.CodeToken
              { IR.codeTokenSourceRange = IR.TextSourceRange offset nextOffset
              , IR.codeTokenText = value
              , IR.codeTokenKind = tokenKind kind
              }
       in (nextOffset, result ++ [token])
    projectLine sourceTokens (range, display) = do
      let result = Maybe.mapMaybe (sliceToken range) sourceTokens
          rendered = concatMap IR.codeTokenText result
      if rendered /= display
        then Left "syntax highlighter did not preserve verbatim code text"
        else case reverse result of
               token:_
                 | IR.textSourceRangeEnd (IR.codeTokenSourceRange token)
                     > IR.textSourceRangeEnd range ->
                   Left "syntax highlighter produced an invalid source range"
               _ -> Right result

sliceToken :: IR.TextSourceRange -> IR.CodeToken -> Maybe IR.CodeToken
sliceToken target token
  | overlapStart >= overlapEnd = Nothing
  | otherwise =
    Just
      token
        { IR.codeTokenSourceRange = IR.TextSourceRange overlapStart overlapEnd
        , IR.codeTokenText =
            Text.unpack
              (TextEncoding.decodeUtf8
                 (BS.take
                    (overlapEnd - overlapStart)
                    (BS.drop
                       (overlapStart - tokenStart)
                       (TextEncoding.encodeUtf8
                          (Text.pack (IR.codeTokenText token))))))
        }
  where
    tokenRange = IR.codeTokenSourceRange token
    tokenStart = IR.textSourceRangeStart tokenRange
    tokenEnd = IR.textSourceRangeEnd tokenRange
    targetStart = IR.textSourceRangeStart target
    targetEnd = IR.textSourceRangeEnd target
    overlapStart = max tokenStart targetStart
    overlapEnd = min tokenEnd targetEnd

physicalLines :: String -> [(Int, String)]
physicalLines = go 0
  where
    go offset input =
      let (line, rest) = break (== '\n') input
          nextOffset = offset + utf8Length line
       in (offset, line)
            : case rest of
                []      -> []
                _:after -> go (nextOffset + 1) after

tokenKind :: Sky.TokenType -> IR.CodeTokenKind
tokenKind kind =
  case kind of
    Sky.KeywordTok        -> IR.CodeKeyword
    Sky.ControlFlowTok    -> IR.CodeKeyword
    Sky.ImportTok         -> IR.CodeKeyword
    Sky.DataTypeTok       -> IR.CodeType
    Sky.BuiltInTok        -> IR.CodeType
    Sky.DecValTok         -> IR.CodeNumber
    Sky.BaseNTok          -> IR.CodeNumber
    Sky.FloatTok          -> IR.CodeNumber
    Sky.ConstantTok       -> IR.CodeNumber
    Sky.CharTok           -> IR.CodeString
    Sky.SpecialCharTok    -> IR.CodeString
    Sky.StringTok         -> IR.CodeString
    Sky.VerbatimStringTok -> IR.CodeString
    Sky.SpecialStringTok  -> IR.CodeString
    Sky.CommentTok        -> IR.CodeComment
    Sky.DocumentationTok  -> IR.CodeComment
    Sky.CommentVarTok     -> IR.CodeComment
    Sky.FunctionTok       -> IR.CodeFunction
    Sky.VariableTok       -> IR.CodeVariable
    Sky.OperatorTok       -> IR.CodeOperator
    Sky.ErrorTok          -> IR.CodeError
    Sky.AlertTok          -> IR.CodeError
    Sky.WarningTok        -> IR.CodeError
    _                     -> IR.CodeNormal

syntaxXml :: LanguageDefinition -> String
syntaxXml definition =
  concat
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    , "<language name=\""
    , languageName definition
    , "\" section=\"Sources\" version=\"1\" kateversion=\"5.0\" extensions=\"\" license=\"BSD-3-Clause\">"
    , "<highlighting><list name=\"keywords\">"
    , concatMap
        (\keyword -> "<item>" ++ keyword ++ "</item>")
        (languageKeywords definition)
    , "</list><contexts>"
    , "<context name=\"Normal\" lineEndContext=\"#stay\" attribute=\"Normal\">"
    , concatMap lineCommentRule (languageLineComments definition)
    , concatMap
        blockCommentRule
        (zip [0 :: Int ..] (languageBlockComments definition))
    , "<DetectChar char=\"&quot;\" context=\"DoubleString\" attribute=\"String\"/>"
    , "<DetectChar char=\"'\" context=\"SingleString\" attribute=\"String\"/>"
    , "<keyword String=\"keywords\" context=\"#stay\" attribute=\"Keyword\"/>"
    , "<Float context=\"#stay\" attribute=\"Number\"/>"
    , "<Int context=\"#stay\" attribute=\"Number\"/>"
    , "</context>"
    , "<context name=\"DoubleString\" lineEndContext=\"#pop\" attribute=\"String\">"
    , "<HlCStringChar context=\"#stay\" attribute=\"String\"/>"
    , "<DetectChar char=\"&quot;\" context=\"#pop\" attribute=\"String\"/>"
    , "</context>"
    , "<context name=\"SingleString\" lineEndContext=\"#pop\" attribute=\"String\">"
    , "<HlCStringChar context=\"#stay\" attribute=\"String\"/>"
    , "<DetectChar char=\"'\" context=\"#pop\" attribute=\"String\"/>"
    , "</context>"
    , "<context name=\"LineComment\" lineEndContext=\"#pop\" attribute=\"Comment\"/>"
    , concatMap
        blockCommentContext
        (zip [0 :: Int ..] (languageBlockComments definition))
    , "</contexts><itemDatas>"
    , "<itemData name=\"Normal\" defStyleNum=\"dsNormal\"/>"
    , "<itemData name=\"Keyword\" defStyleNum=\"dsKeyword\"/>"
    , "<itemData name=\"Number\" defStyleNum=\"dsDecVal\"/>"
    , "<itemData name=\"String\" defStyleNum=\"dsString\"/>"
    , "<itemData name=\"Comment\" defStyleNum=\"dsComment\"/>"
    , "</itemDatas></highlighting></language>"
    ]

lineCommentRule :: (Char, Maybe Char) -> String
lineCommentRule (first, Nothing) =
  "<DetectChar char=\""
    ++ xmlChar first
    ++ "\" context=\"LineComment\" attribute=\"Comment\"/>"
lineCommentRule (first, Just second) =
  concat
    [ "<Detect2Chars char=\""
    , xmlChar first
    , "\" char1=\""
    , xmlChar second
    , "\" context=\"LineComment\" attribute=\"Comment\"/>"
    ]

blockCommentRule :: (Int, ((Char, Char), (Char, Char))) -> String
blockCommentRule (index, ((first, second), _)) =
  concat
    [ "<Detect2Chars char=\""
    , xmlChar first
    , "\" char1=\""
    , xmlChar second
    , "\" context=\"BlockComment"
    , show index
    , "\" attribute=\"Comment\"/>"
    ]

blockCommentContext :: (Int, ((Char, Char), (Char, Char))) -> String
blockCommentContext (index, (_, (first, second))) =
  concat
    [ "<context name=\"BlockComment"
    , show index
    , "\" lineEndContext=\"#stay\" attribute=\"Comment\">"
    , "<Detect2Chars char=\""
    , xmlChar first
    , "\" char1=\""
    , xmlChar second
    , "\" context=\"#pop\" attribute=\"Comment\"/></context>"
    ]

xmlChar :: Char -> String
xmlChar value =
  case value of
    '&' -> "&amp;"
    '<' -> "&lt;"
    '>' -> "&gt;"
    '"' -> "&quot;"
    _   -> [value]

normalize :: String -> String
normalize = map Char.toLower

padTo :: Int -> [Sky.SourceLine] -> [Sky.SourceLine]
padTo count values = take count (values ++ repeat [])

utf8Length :: String -> Int
utf8Length = BS.length . TextEncoding.encodeUtf8 . Text.pack

languageDefinitions :: Map.Map String LanguageDefinition
languageDefinitions = Map.fromList (concatMap aliases definitions)
  where
    aliases (names, definition) = [(name, definition) | name <- names]
    definitions =
      [ ( ["sverlin", "haskell", "hs"]
        , language
            "Haskell"
            [ "case"
            , "class"
            , "data"
            , "deriving"
            , "do"
            , "else"
            , "family"
            , "forall"
            , "if"
            , "import"
            , "in"
            , "infix"
            , "infixl"
            , "infixr"
            , "instance"
            , "let"
            , "module"
            , "newtype"
            , "of"
            , "then"
            , "type"
            , "where"
            ]
            [('-', Just '-')]
            [(('{', '-'), ('-', '}'))])
      , ( [ "javascript"
          , "js"
          , "typescript"
          , "ts"
          , "tsx"
          , "java"
          , "c"
          , "cpp"
          , "c++"
          , "go"
          , "rust"
          ]
        , language
            "C-like"
            [ "async"
            , "await"
            , "break"
            , "case"
            , "class"
            , "const"
            , "continue"
            , "default"
            , "do"
            , "else"
            , "enum"
            , "export"
            , "extends"
            , "false"
            , "for"
            , "function"
            , "if"
            , "implements"
            , "import"
            , "in"
            , "interface"
            , "let"
            , "match"
            , "new"
            , "null"
            , "package"
            , "private"
            , "public"
            , "return"
            , "static"
            , "struct"
            , "switch"
            , "throw"
            , "trait"
            , "true"
            , "try"
            , "type"
            , "var"
            , "while"
            , "yield"
            ]
            [('/', Just '/')]
            [(('/', '*'), ('*', '/'))])
      , ( ["python", "py", "bash", "sh"]
        , language
            "Python-like"
            [ "and"
            , "as"
            , "assert"
            , "async"
            , "await"
            , "break"
            , "case"
            , "class"
            , "continue"
            , "def"
            , "del"
            , "elif"
            , "else"
            , "except"
            , "false"
            , "finally"
            , "for"
            , "from"
            , "global"
            , "if"
            , "import"
            , "in"
            , "is"
            , "lambda"
            , "match"
            , "none"
            , "nonlocal"
            , "not"
            , "or"
            , "pass"
            , "raise"
            , "return"
            , "true"
            , "try"
            , "while"
            , "with"
            , "yield"
            ]
            [('#', Nothing)]
            [])
      , (["json"], language "JSON" ["false", "null", "true"] [] [])
      , (["css"], language "CSS" [] [] [(('/', '*'), ('*', '/'))])
      , ( ["sql"]
        , language
            "SQL"
            [ "and"
            , "as"
            , "asc"
            , "by"
            , "case"
            , "create"
            , "delete"
            , "desc"
            , "distinct"
            , "drop"
            , "else"
            , "end"
            , "from"
            , "full"
            , "group"
            , "having"
            , "in"
            , "inner"
            , "insert"
            , "into"
            , "join"
            , "left"
            , "limit"
            , "not"
            , "null"
            , "on"
            , "or"
            , "order"
            , "outer"
            , "right"
            , "select"
            , "set"
            , "table"
            , "then"
            , "union"
            , "update"
            , "values"
            , "when"
            , "where"
            ]
            [('-', Just '-')]
            [(('/', '*'), ('*', '/'))])
      ]
    language = LanguageDefinition
