-- editorconfig-checker-disable-file
{-# LANGUAGE FlexibleContexts #-}
-- | Functions for computing variable usage inside terms and types.
module PlutusIR.Analysis.Usages (runTermUsages, runTypeUsages, Usages, getUsageCount, allUsed) where

import PlutusIR

import PlutusCore qualified as PLC
import PlutusCore.Name qualified as PLC

import Control.Lens
import Control.Monad.State

import Data.Coerce
import Data.Foldable
import Data.Map qualified as Map
import Data.Set qualified as Set

-- | Variable uses, as a map from the 'PLC.Unique' to its usage count. Unused variables may be missing
-- or have usage count 0.
type Usages = Map.Map PLC.Unique Int

addUsage :: (PLC.HasUnique n unique) => n -> Usages -> Usages
addUsage n usages =
    let
        u = coerce $ n ^. PLC.unique
        old = Map.findWithDefault 0 u usages
    in Map.insert u (old+1) usages

-- | Get the usage count of @n@.
getUsageCount :: (PLC.HasUnique n unique) => n -> Usages -> Int
getUsageCount n usages = Map.findWithDefault 0 (n ^. PLC.unique . coerced) usages

-- | Get a set of @n@s which are used at least once.
allUsed :: Usages -> Set.Set PLC.Unique
allUsed usages = Map.keysSet $ Map.filter (> 0) usages

-- | Compute the 'Usages' for a 'Term'.
runTermUsages
    :: (PLC.HasUnique name PLC.TermUnique, PLC.HasUnique tyname PLC.TypeUnique)
    => Term tyname name uni fun a
    -> Usages
runTermUsages term = execState (termUsages term) mempty

-- | Compute the 'Usages' for a 'Type'.
runTypeUsages
    ::(PLC.HasUnique tyname PLC.TypeUnique)
    => Type tyname uni a
    -> Usages
runTypeUsages ty = execState (typeUsages ty) mempty

termUsages
    :: (MonadState Usages m, PLC.HasUnique name PLC.TermUnique, PLC.HasUnique tyname PLC.TypeUnique)
    => Term tyname name uni fun a
    -> m ()
termUsages (Var _ n) = modify (addUsage n)
termUsages term      = traverse_ termUsages (term ^.. termSubterms) >> traverse_ typeUsages (term ^.. termSubtypes)

-- TODO: move to plutus-core
typeUsages
    :: (MonadState Usages m, PLC.HasUnique tyname PLC.TypeUnique)
    => Type tyname uni a
    -> m ()
typeUsages (TyVar _ n) = modify (addUsage n)
typeUsages ty          = traverse_ typeUsages (ty ^.. typeSubtypes)
