{-# LANGUAGE TemplateHaskell #-}

module Main where

import           GenerateVisualizationTypes.TypeScript (generateDeclarations)
import           Sverlin.Output.IR                     as IR

main :: IO ()
main = putStr (unlines $(generateDeclarations ''IR.Visualization))
