-- | This module contains all the public API types for the component.
module Component.Wallets.Types where

import Halogen as H
import Halogen.HTML as HH

data Query a

type Input
  = {
    }

data Msg

type Slot
  = H.Slot Query

type Component
  = H.Component HH.HTML Query Input Msg
