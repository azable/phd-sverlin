{-# LANGUAGE TemplateHaskell #-}

module Main where

import           LinearTrace.Visualization.IR as IR
import           GenerateVisualizationTypes.TypeScript (generateDeclarations)

main :: IO ()
main = putStr (unlines $(generateDeclarations ''IR.VisualizationPackage))
