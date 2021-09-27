-- | This module contains the implementation and entry point of the component
module Component.Wallets
  ( component
  , module Component.Wallets.Types
  ) where

import Prologue
import Component.Wallets.Types (Component, Input, Msg, Query, Slot)
import Halogen as H
import Halogen.HTML (text)

-------------------------------------------------------------------------------
-- Private types
-------------------------------------------------------------------------------
data Action
  = Init
  | Receive Input

type State
  = {
    }

type Slots
  = (
    )

type DSL
  = H.HalogenM State Action Slots Msg

type ComponentHTML m
  = H.ComponentHTML Action Slots m

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
component :: forall m. Monad m => Component m
component =
  H.mkComponent
    { initialState
    , render
    , eval:
        H.mkEval
          H.defaultEval
            { handleAction = handleAction
            , initialize = Just Init
            , receive = Just <<< Receive
            }
    }

initialState :: Input -> State
initialState input = {}

-------------------------------------------------------------------------------
-- Rendering
-------------------------------------------------------------------------------
render :: forall m. Monad m => State -> ComponentHTML m
render state = text "hello, world"

-------------------------------------------------------------------------------
-- Handlers
-------------------------------------------------------------------------------
handleAction :: forall m. Monad m => Action -> DSL m Unit
handleAction = case _ of
  Init -> pure unit
  Receive {} -> pure unit
