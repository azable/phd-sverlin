{-# LANGUAGE TemplateHaskell #-}

module Main where

import           GenerateVisualizationTypes.TypeScript (generateDeclarations)
import           LinearTrace.Visualization.IR          as IR

main :: IO ()
main = putStr (unlines $(generateDeclarations ''IR.VisualizationPackage))
