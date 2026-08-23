{-# LANGUAGE ForeignFunctionInterface #-}

-- | Minimal, internal HarfBuzz binding used by compiler-owned text layout.
--
-- The C shim owns structure layout and copies font bytes into an immutable
-- HarfBuzz blob. Keeping this boundary narrow avoids exposing a general FFI as
-- Sverlin API and makes the values serialized into text-run resources explicit.
module LinearTrace.Visualization.HarfBuzz
  ( ShapeOptions(..)
  , defaultShapeOptions
  , ShapedGlyph(..)
  , ShapedText(..)
  , harfBuzzVersion
  , shapeText
  ) where

import           Control.Exception      (bracket)
import qualified Data.ByteString        as BS
import qualified Data.ByteString.Unsafe as BS
import           Data.Int               (Int32)
import qualified Data.Text              as Text
import qualified Data.Text.Encoding     as Text
import           Data.Word              (Word32, Word8)
import           Foreign.C.String       (CString, peekCString)
import           Foreign.C.Types        (CFloat (..), CInt (..), CSize (..),
                                         CUInt (..))
import           Foreign.Marshal.Alloc  (alloca)
import           Foreign.Ptr            (Ptr, castPtr, nullPtr)
import           Foreign.Storable       (peek)
import           Prelude
import           System.IO.Unsafe       (unsafePerformIO)

data ShapeOptions = ShapeOptions
  { shapeOptionWeight           :: Int
  , shapeOptionDisableLigatures :: Bool
  } deriving (Eq, Show)

defaultShapeOptions :: ShapeOptions
defaultShapeOptions =
  ShapeOptions {shapeOptionWeight = 400, shapeOptionDisableLigatures = False}

data ShapedGlyph = ShapedGlyph
  { shapedGlyphId       :: Word32
  , shapedGlyphCluster  :: Word32
  , shapedGlyphXAdvance :: Int32
  , shapedGlyphYAdvance :: Int32
  , shapedGlyphXOffset  :: Int32
  , shapedGlyphYOffset  :: Int32
  , shapedGlyphXBearing :: Int32
  , shapedGlyphYBearing :: Int32
  , shapedGlyphWidth    :: Int32
  , shapedGlyphHeight   :: Int32
  } deriving (Eq, Show)

data ShapedText = ShapedText
  { shapedTextUnitsPerEm  :: Word32
  , shapedTextAscender    :: Int32
  , shapedTextDescender   :: Int32
  , shapedTextLineGap     :: Int32
  , shapedTextScript      :: String
  , shapedTextRightToLeft :: Bool
  , shapedTextGlyphs      :: [ShapedGlyph]
  } deriving (Eq, Show)

data CShapeResult

harfBuzzVersion :: String
harfBuzzVersion = unsafePerformIO (cVersionString >>= peekCString)

{-# NOINLINE harfBuzzVersion #-}
shapeText ::
     BS.ByteString -> ShapeOptions -> String -> IO (Either String ShapedText)
shapeText fontBytes options source =
  BS.unsafeUseAsCStringLen fontBytes $ \(fontPointer, fontLength) ->
    BS.unsafeUseAsCStringLen (Text.encodeUtf8 (Text.pack source)) $ \(textPointer, textLength) ->
      alloca $ \resultPointer -> do
        status <-
          cShape
            (castBytePointer fontPointer)
            (fromIntegral fontLength)
            textPointer
            (fromIntegral textLength)
            (fromIntegral (shapeOptionWeight options))
            (if shapeOptionDisableLigatures options
               then 1
               else 0)
            resultPointer
        result <- peek resultPointer
        if status /= 0 || result == nullPtr
          then pure (Left (shapeStatusMessage status))
          else Right <$> bracket (pure result) cShapeDestroy readShape

readShape :: Ptr CShapeResult -> IO ShapedText
readShape result = do
  glyphCount <- (fromIntegral <$> cGlyphCount result) :: IO Int
  ShapedText
    <$> cUpem result
    <*> cAscender result
    <*> cDescender result
    <*> cLineGap result
    <*> (scriptTag <$> cScriptTag result)
    <*> ((/= 0) <$> cIsRtl result)
    <*> traverse (readGlyph result . fromIntegral) [0 .. glyphCount - 1]

readGlyph :: Ptr CShapeResult -> CUInt -> IO ShapedGlyph
readGlyph result index =
  ShapedGlyph
    <$> cGlyphId result index
    <*> cGlyphCluster result index
    <*> cGlyphXAdvance result index
    <*> cGlyphYAdvance result index
    <*> cGlyphXOffset result index
    <*> cGlyphYOffset result index
    <*> cGlyphXBearing result index
    <*> cGlyphYBearing result index
    <*> cGlyphWidth result index
    <*> cGlyphHeight result index

scriptTag :: Word32 -> String
scriptTag tag =
  [ toEnum (fromIntegral ((tag `div` 0x1000000) `mod` 0x100))
  , toEnum (fromIntegral ((tag `div` 0x10000) `mod` 0x100))
  , toEnum (fromIntegral ((tag `div` 0x100) `mod` 0x100))
  , toEnum (fromIntegral (tag `mod` 0x100))
  ]

shapeStatusMessage :: CInt -> String
shapeStatusMessage status =
  case status of
    1 -> "HarfBuzz rejected invalid shaping arguments"
    2 -> "the selected font is not a valid OpenType face"
    3 -> "HarfBuzz could not allocate a shaping result"
    4 -> "HarfBuzz could not shape the supplied text"
    _ -> "HarfBuzz failed with status " ++ show status

castBytePointer :: CString -> Ptr Word8
castBytePointer = castPtr

foreign import ccall unsafe "sverlin_hb_shape" cShape :: Ptr Word8 -> CSize -> CString -> CInt -> CFloat -> CInt -> Ptr
                                                                                                                      (Ptr
                                                                                                                         CShapeResult) -> IO
                                                                                                                                            CInt

foreign import ccall unsafe "sverlin_hb_shape_destroy" cShapeDestroy :: Ptr
  CShapeResult -> IO ()

foreign import ccall unsafe "sverlin_hb_version_string" cVersionString :: IO
  CString

foreign import ccall unsafe "sverlin_hb_upem" cUpem :: Ptr CShapeResult -> IO
                                                                             Word32

foreign import ccall unsafe "sverlin_hb_ascender" cAscender :: Ptr CShapeResult -> IO
                                                                                     Int32

foreign import ccall unsafe "sverlin_hb_descender" cDescender :: Ptr
  CShapeResult -> IO Int32

foreign import ccall unsafe "sverlin_hb_line_gap" cLineGap :: Ptr CShapeResult -> IO
                                                                                    Int32

foreign import ccall unsafe "sverlin_hb_script_tag" cScriptTag :: Ptr
  CShapeResult -> IO Word32

foreign import ccall unsafe "sverlin_hb_is_rtl" cIsRtl :: Ptr CShapeResult -> IO
                                                                                CInt

foreign import ccall unsafe "sverlin_hb_glyph_count" cGlyphCount :: Ptr
  CShapeResult -> IO CUInt

foreign import ccall unsafe "sverlin_hb_glyph_id" cGlyphId :: Ptr CShapeResult -> CUInt -> IO
                                                                                             Word32

foreign import ccall unsafe "sverlin_hb_glyph_cluster" cGlyphCluster :: Ptr
  CShapeResult -> CUInt -> IO Word32

foreign import ccall unsafe "sverlin_hb_glyph_x_advance" cGlyphXAdvance :: Ptr
  CShapeResult -> CUInt -> IO Int32

foreign import ccall unsafe "sverlin_hb_glyph_y_advance" cGlyphYAdvance :: Ptr
  CShapeResult -> CUInt -> IO Int32

foreign import ccall unsafe "sverlin_hb_glyph_x_offset" cGlyphXOffset :: Ptr
  CShapeResult -> CUInt -> IO Int32

foreign import ccall unsafe "sverlin_hb_glyph_y_offset" cGlyphYOffset :: Ptr
  CShapeResult -> CUInt -> IO Int32

foreign import ccall unsafe "sverlin_hb_glyph_x_bearing" cGlyphXBearing :: Ptr
  CShapeResult -> CUInt -> IO Int32

foreign import ccall unsafe "sverlin_hb_glyph_y_bearing" cGlyphYBearing :: Ptr
  CShapeResult -> CUInt -> IO Int32

foreign import ccall unsafe "sverlin_hb_glyph_width" cGlyphWidth :: Ptr
  CShapeResult -> CUInt -> IO Int32

foreign import ccall unsafe "sverlin_hb_glyph_height" cGlyphHeight :: Ptr
  CShapeResult -> CUInt -> IO Int32
