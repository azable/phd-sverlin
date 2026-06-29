{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE RebindableSyntax  #-}
{-# LANGUAGE TypeApplications  #-}

module ChoreographySemanticTest
  ( unitViewGraph
  , angleViewGraph
  ) where

import           Control.Functor.Linear   hiding ((<$>), (<*>))
import           LinearTrace.Choreography
import qualified LinearTrace.View         as View
import           Prelude.Linear           hiding (fromInteger, fromRational,
                                           (*), (+), (-), (/), (/=), (<>))

unitViewGraph :: View.ViewGraph
unitViewGraph =
  View.buildCSP
    (runProgramWith
       (visualize $ do
          Variable unitValue <-
            (variable @Unit :: VisualizationBuilder (Variable Unit))
          ensure (unitValue .==. (num 0.5 :: Unit)))
       (return ()))

angleViewGraph :: View.ViewGraph
angleViewGraph =
  View.buildCSP
    (runProgramWith
       (visualize $ do
          Variable angleValue <-
            (variable @Angle :: VisualizationBuilder (Variable Angle))
          ensure (angleValue .==. (num 180 :: Angle)))
       (return ()))
