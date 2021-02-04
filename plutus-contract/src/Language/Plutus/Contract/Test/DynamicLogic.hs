{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE GADTs                     #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE StandaloneDeriving        #-}
{-# LANGUAGE TypeApplications          #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

module Language.Plutus.Contract.Test.DynamicLogic
    ( module Language.Plutus.Contract.Test.DynamicLogic.Quantify
    , DynLogic, DynPred
    , DynLogicModel(..)
    , ignore, passTest, afterAny, after, (|||), forAllQ, weight, toStop
    , done, always
    , forAllScripts
    ) where

import           Data.Typeable

import           Test.QuickCheck

import           Language.Plutus.Contract.Test.DynamicLogic.CanGenerate
import           Language.Plutus.Contract.Test.DynamicLogic.Quantify
import           Language.Plutus.Contract.Test.StateModel


data DynLogic s = EmptySpec
                | Stop
                | AfterAny (DynPred s)
                | Alt Bool (DynLogic s) (DynLogic s)  -- True for angelic
                | Stopping (DynLogic s)
                | After (Any (Action s)) (DynPred s)
                | Weight Double (DynLogic s)
                | forall a. (Eq a, Show a, Typeable a) =>
                    ForAll (Quantification a) (a -> DynLogic s)

type DynPred s = s -> DynLogic s

-- API for building formulae

ignore    :: DynLogic s
passTest  :: DynLogic s
afterAny  :: DynPred s -> DynLogic s
after     :: (Show a, Typeable a, Eq (Action s a)) =>
               Action s a -> DynPred s -> DynLogic s
(|||)     :: DynLogic s -> DynLogic s -> DynLogic s
forAllQ   :: Quantifiable q =>
               q -> (Quantifies q -> DynLogic s) -> DynLogic s
weight    :: Double -> DynLogic s -> DynLogic s
toStop    :: DynLogic s -> DynLogic s

done      :: DynPred s
always    :: DynPred s -> DynPred s

ignore       = EmptySpec
passTest     = Stop
afterAny     = AfterAny
after act    = After (Some act)
(|||)        = Alt True  -- In formulae, we use only angelic
                         -- choice. But it becomes demonic after one
                         -- step (that is, the choice has been made).
forAllQ q f
    | isEmptyQ q' = ignore
    | otherwise   = ForAll q' f
    where q' = quantify q

weight       = Weight
toStop       = Stopping

done _       = passTest

always p s   = Stopping (p s) ||| Weight 0.1 (p s) ||| AfterAny (always p)

data DynLogicTest s = BadPrecondition [TestStep s] [Any (Action s)]
                    | Looping [TestStep s]
                    | Stuck [TestStep s]
                    | DLScript [TestStep s]

data TestStep s = Do (Step s)
                | forall a. (Eq a, Show a, Typeable a) => Witness a

instance Eq (TestStep s) where
    Do s == Do s' = s == s'
    Witness (a :: a) == Witness (a' :: a') =
        case eqT @a @a' of
            Just Refl -> a == a'
            Nothing   -> False
    _ == _ = False

instance StateModel s => Show (TestStep s) where
  show (Do step)   = "Do $ "++show step
  show (Witness a) = "Witness ("++show a++" :: "++show (typeOf a)++")"


instance StateModel s => Show (DynLogicTest s) where
    show (BadPrecondition as bads) =
        unlines $ ["BadPrecondition"] ++ bracket (map show as) ++ ["  " ++ show bads]
    show (Looping as) =
        unlines $ ["Looping"] ++ bracket (map show as)
    show (Stuck as) =
        unlines $ ["Stuck"] ++ bracket (map show as)
    show (DLScript as) =
        unlines $ ["DLScript"] ++ bracket (map show as)

bracket :: [String] -> [String]
bracket []  = ["  []"]
bracket [s] = ["  [" ++ s ++ "]"]
bracket (first:rest) = ["  ["++first++", "] ++
                       map (("   "++).(++", ")) (reverse middle) ++
                       ["   "++last++"]"]
    where last:middle = reverse rest

-- Restricted calls are not generated by "AfterAny"; they are included
-- in tests explicitly using "After" in order to check specific
-- properties at controlled times, so they are likely to fail if
-- invoked at other times.

class StateModel s => DynLogicModel s where
    restricted :: Action s a -> Bool
    restricted _ = False

forAllScripts :: (DynLogicModel s, Testable a) =>
                   DynLogic s -> (Script s -> a) -> Property
forAllScripts d k =
    forAllShrink (sized $ generateDLTest d) (shrinkDLTest d) $ \test ->
        validDLTest d test .&&. k (scriptFromDL test)

generateDLTest :: DynLogicModel s => DynLogic s -> Int -> Gen (DynLogicTest s)
generateDLTest d size = generate d 0 (initialStateFor d) []
    where
        generate d n s as =
            case badActions d s of
                [] ->
                    if n > sizeLimit size then
                        return $ Looping (reverse as)
                    else do
                        let preferred = if n > size then stopping d else noStopping d
                            useStep StoppingStep _ = return $ DLScript (reverse as)
                            useStep (Stepping (Do (var := act)) d') _ =
                              generate d'
                                       (n+1)
                                       (nextState s act var)
                                       (Do (var := act):as)
                            useStep (Stepping (Witness a) d') _ =
                              generate d' n s (Witness a:as)
                            useStep NoStep alt = alt
                        foldr (\ step k -> do try <- chooseNextStep s n step; useStep try k)
                              (return $ Stuck (reverse as))
                              [preferred, noAny preferred, d, noAny d]
                bs -> return $ BadPrecondition (reverse as) bs

sizeLimit :: Int -> Int
sizeLimit size = 2 * size + 20

initialStateFor :: StateModel s => DynLogic s -> s
initialStateFor _ = initialState

stopping :: DynLogic s -> DynLogic s
stopping EmptySpec     = EmptySpec
stopping Stop          = Stop
stopping (After act k) = After act k
stopping (AfterAny _)  = EmptySpec
stopping (Alt b d d')  = Alt b (stopping d) (stopping d')
stopping (Stopping d)  = d
stopping (Weight w d)  = Weight w (stopping d)
stopping (ForAll _ _)  = EmptySpec

noStopping :: DynLogic s -> DynLogic s
noStopping EmptySpec     = EmptySpec
noStopping Stop          = EmptySpec
noStopping (After act k) = After act k
noStopping (AfterAny k)  = AfterAny k
noStopping (Alt b d d')  = Alt b (noStopping d) (noStopping d')
noStopping (Stopping _)  = EmptySpec
noStopping (Weight w d)  = Weight w (noStopping d)
noStopping (ForAll q f)  = ForAll q f

noAny :: DynLogic s -> DynLogic s
noAny EmptySpec     = EmptySpec
noAny Stop          = Stop
noAny (After act k) = After act k
noAny (AfterAny _)  = EmptySpec
noAny (Alt b d d')  = Alt b (noAny d) (noAny d')
noAny (Stopping d)  = Stopping (noAny d)
noAny (Weight w d)  = Weight w (noAny d)
noAny (ForAll q f)  = ForAll q f

nextSteps :: DynLogic s -> [(Double, DynLogic s)]
nextSteps EmptySpec     = []
nextSteps Stop          = [(1, Stop)]
nextSteps (After act k)=[(1, After act k)]
nextSteps (AfterAny k)  = [(1, AfterAny k)]
nextSteps (Alt _ d d')  = nextSteps d ++ nextSteps d'
nextSteps (Stopping d)  = nextSteps d
nextSteps (Weight w d)  = [(w*w', s) | (w', s) <- nextSteps d, w*w' > never]
nextSteps (ForAll q f)  = [(1, ForAll q f)]

chooseOneOf :: [(Double, DynLogic s)] -> Gen (DynLogic s)
chooseOneOf steps = frequency [(round (w/never), return s) | (w, s) <- steps]

never :: Double
never = 1.0e-9

data NextStep s = StoppingStep
                | Stepping (TestStep s) (DynLogic s)
                | NoStep

chooseNextStep :: DynLogicModel s => s -> Int -> DynLogic s -> Gen (NextStep s)
chooseNextStep s n d =
    case nextSteps d of
        [] -> return NoStep
        steps -> do
            chosen <- chooseOneOf steps
            case chosen of
                EmptySpec  -> return NoStep
                Stop       -> return StoppingStep
                After (Some a) k ->
                    return $ Stepping (Do $ Var n := a) (k (nextState s a (Var n)))
                AfterAny k -> do
                    m <- keepTryingUntil 100 (arbitraryAction s) $
                          \(Some act) -> precondition s act && not (restricted act)
                    case m of
                        Nothing -> return NoStep
                        Just (Some a) ->
                            return $ Stepping (Do $ Var n := a)
                                              (k (nextState s a (Var n)))
                ForAll q f -> do
                    x <- generateQ q
                    return $ Stepping (Witness x) (f x)
                Alt{}      -> error "chooseNextStep: Alt"
                Stopping{} -> error "chooseNextStep: Stopping"
                Weight{}   -> error "chooseNextStep: Weight"

keepTryingUntil :: Int -> Gen a -> (a -> Bool) -> Gen (Maybe a)
keepTryingUntil 0 _ _ = return Nothing
keepTryingUntil n g p = do
    x <- g
    if p x then return $ Just x else scale (+1) $ keepTryingUntil (n-1) g p


shrinkDLTest :: DynLogicModel s => DynLogic s -> DynLogicTest s -> [DynLogicTest s]
shrinkDLTest _ (Looping _) = []
shrinkDLTest d tc =
    [test | as' <- shrinkScript d (getScript tc),
            let test = makeTestFromPruned d (pruneDLTest d as'),
            -- Don't shrink a non-executable test case to an executable one.
            case (tc, test) of
                (DLScript _, _) -> True
                (_, DLScript _) -> False
                _               -> True]

shrinkScript :: DynLogicModel t => DynLogic t -> [TestStep t] -> [[TestStep t]]
shrinkScript d as = shrink' d as initialState
    where
        shrink' _ [] _ = []
        shrink' d (step:as) s =
          [] :
          reverse (takeWhile (not . null) [drop (n-1) as | n <- iterate (*2) 1]) ++
          case step of
            Do (var := act) ->
              [case (var, a') of (Var i, Some act') -> Do (Var i := act'):as
              | a' <- shrinkAction s act]
            Witness a ->
              -- When we shrink a witness, allow one shrink of the
              -- rest of the script... so assuming the witness may be
              -- used once to construct the rest of the test. If used
              -- more than once, we may need double shrinking.
              [Witness a':as' | a' <- shrinkWitness d a,
                                as' <- as:shrink' (stepDLtoDL d s (Witness a')) as s]
          ++ [step:as'
             | as' <- shrink' (stepDLtoDL d s step) as $
                        case step of
                          Do (var := act) -> nextState s act var
                          Witness _       -> s]

shrinkWitness :: (StateModel s, Typeable a) => DynLogic s -> a -> [a]
shrinkWitness (ForAll (q :: Quantification a) _) (a :: a') =
  case eqT @a @a' of
    Just Refl | isaQ q a -> shrinkQ q a
    _                    -> []
shrinkWitness (Alt _ d d') a = shrinkWitness d a ++ shrinkWitness d' a
shrinkWitness (Stopping d) a = shrinkWitness d a
shrinkWitness (Weight _ d) a = shrinkWitness d a
shrinkWitness _ _            = []

-- The result of pruning a list of actions is a list of actions that
-- could have been generated by the dynamic logic.
pruneDLTest :: DynLogicModel s => DynLogic s -> [TestStep s] -> [TestStep s]
pruneDLTest d test = prune [d] initialState test
  where
    prune [] _ _ = []
    prune _ _ [] = []
    prune ds s (Do (var := act):rest)
      | precondition s act =
        case [d' | d <- ds, d' <- stepDL d s (Do $ var := act)] of
          [] -> prune ds s rest
          ds' -> Do (var := act) :
            prune ds' (nextState s act var) rest
      | otherwise =
        prune ds s rest
    prune ds s (Witness a:rest) =
      case [d' | d <- ds, d' <- stepDL d s (Witness a)] of
        []  -> prune ds s rest
        ds' -> Witness a : prune ds' s rest

stepDL :: DynLogicModel s => DynLogic s -> s -> TestStep s -> [DynLogic s]
stepDL (After a k) s (Do (var := act))
  | a == Some act = [k (nextState s act var)]
stepDL (AfterAny k) s (Do (var := act))
  | not (restricted act) = [k (nextState s act var)]
stepDL (Alt _ d d') s step = stepDL d s step ++ stepDL d' s step
stepDL (Stopping d) s step = stepDL d s step
stepDL (Weight _ d) s step = stepDL d s step
stepDL (ForAll (q :: Quantification a) f) _ (Witness (a :: a')) =
  case eqT @ a @ a' of
    Just Refl -> [f a | isaQ q a]
    Nothing   -> []
stepDL _ _ _ = []

stepDLtoDL :: DynLogicModel s => DynLogic s -> s -> TestStep s -> DynLogic s
stepDLtoDL d s step = case stepDL d s step of
                        [] -> EmptySpec
                        ds -> foldr1 (Alt False) ds

propPruningGeneratedScriptIsNoop :: DynLogicModel s => DynLogic s -> Property
propPruningGeneratedScriptIsNoop d =
  forAll (sized $ \ n -> choose (1, max 1 n) >>= generateDLTest d) $ \test ->
    let script = case test of BadPrecondition s _ -> s
                              Looping s           -> s
                              Stuck s             -> s
                              DLScript s          -> s
    in script == pruneDLTest d script

getScript :: DynLogicTest s -> [TestStep s]
getScript (BadPrecondition s _) = s
getScript (Looping s)           = s
getScript (Stuck s)             = s
getScript (DLScript s)          = s

makeTestFromPruned :: DynLogicModel s => DynLogic s -> [TestStep s] -> DynLogicTest s
makeTestFromPruned d test = make d initialState test
  where make d s as | not (null bad) = BadPrecondition as bad
          where bad = badActions d s
        make d s [] | stuck d s = Stuck []
                    | otherwise = DLScript []
        make d s (step:as) =
          case make (stepDLtoDL d s step)
                    (case step of
                       Do (var := act) -> nextState s act var
                       Witness _       -> s)
                    as
          of
            BadPrecondition as bad -> BadPrecondition (step:as) bad
            Stuck as               -> Stuck (step:as)
            DLScript as            -> DLScript (step:as)
            Looping{}              -> error "makeTestFromPruned: Looping"

stuck :: DynLogicModel s => DynLogic s -> s -> Bool
stuck EmptySpec    _ = True
stuck Stop         _ = False
stuck (After _ _)  _ = False
stuck (AfterAny _) s = not $ canGenerate 0.01 (arbitraryAction s)
                              (\(Some act) -> precondition s act
                                              && not (restricted act))
stuck (Alt True d d') s  = stuck d s && stuck d' s
stuck (Alt False d d') s = stuck d s || stuck d' s
stuck (Stopping d) s     = stuck d s
stuck (Weight w d) s     = w < never || stuck d s
stuck (ForAll _ _) _     = False

--canGenerate g p = unsafeGenerate $ isJust <$> keepTryingUntil 100 g p


validDLTest :: DynLogic s -> DynLogicTest s -> Bool
validDLTest _ (DLScript _) = True
validDLTest _ _            = False

scriptFromDL :: DynLogicTest s -> Script s
scriptFromDL (DLScript s) = Script [a | Do a <- s]
scriptFromDL _            = Script []

badActions :: StateModel s => DynLogic s -> s -> [Any (Action s)]
badActions EmptySpec _    = []
badActions Stop      _    = []
badActions (After (Some a) _) s
  | precondition s a = []
  | otherwise        = [Some a]
badActions (AfterAny _) _ = []
badActions (Alt _ d d') s = badActions d s ++ badActions d' s
badActions (Stopping d) s = badActions d s
badActions (Weight w d) s = if w < never then [] else badActions d s
badActions (ForAll _ _) _ = []
