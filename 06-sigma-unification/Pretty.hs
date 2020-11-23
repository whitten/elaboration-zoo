
module Pretty (prettyTm, showTm0, displayMetas) where

import Control.Monad
import Data.IORef
import Text.Printf
import Data.List (sortBy)
import Data.Ord (comparing)

import qualified Data.IntMap.Strict as IM

import Common
import Evaluation
import Metacontext
import Syntax

--------------------------------------------------------------------------------

fresh :: [Name] -> Name -> Name
fresh ns "_" = "_"
fresh ns x | elem x ns = fresh ns (x ++ "'")
           | otherwise = x

-- printing precedences
-- atomp = 6  :: Int -- U, var
projp = 5  :: Int -- projection
appp  = 4  :: Int -- application
sgp   = 3  :: Int -- sigma type
pip   = 2  :: Int -- pi type
letp  = 1  :: Int -- let, lambda
pairp = 0  :: Int -- pairs

-- Wrap in parens if expression precedence is lower than
-- enclosing expression precedence.
par :: Int -> Int -> ShowS -> ShowS
par p p' = showParen (p' < p)

prettyTm :: Int -> [Name] -> Tm -> ShowS
prettyTm prec = go prec where

  bracket :: ShowS -> ShowS
  bracket ss = ('{':).ss.('}':)

  piBind ns x Expl a = showParen True ((x++) . (" : "++) . go pairp ns a)
  piBind ns x Impl a = bracket        ((x++) . (" : "++) . go pairp ns a)

  lamBind x Impl = bracket (x++)
  lamBind x Expl = (x++)

  goPr :: Int -> [Name] -> [Name] -> Tm -> Pruning -> ShowS
  goPr p topNs ns t pr = goPr' p ns pr (0 :: Int) where
    goPr' p ns pr x = case (ns, pr) of
      ([]      , []           ) -> go p topNs t
      (ns :> n , pr :> Just i ) -> par p appp $ goPr' appp ns pr (x + 1) . (' ':)
                                   . icit i bracket id (case n of "_" -> (("@"++show x)++); n -> (n++))
      (ns :> n , pr :> Nothing) -> goPr' appp ns pr (x + 1)
      _                         -> impossible

  goIx :: [Name] -> Ix -> ShowS
  goIx ns topIx = go ns topIx where
    go [] _ = impossible
    go ("_":ns) 0 = (("@"++show topIx)++)
    go (n:ns)   0 = (n++)
    go (n:ns)   x = go ns (x - 1)

  go :: Int -> [Name] -> Tm -> ShowS
  go p ns = \case
    Var x                     -> goIx ns x
    Meta m                    -> (("?"++show m)++)
    AppPruning t pr           -> goPr p ns ns t pr
    U                         -> ("U"++)

    Proj1 t                   -> par p projp $ go projp ns t . (".₁"++)
    Proj2 t                   -> par p projp $ go projp ns t . (".₂"++)
    ProjField t x n           -> par p projp $ go projp ns t . ("." ++) . (x++)

    App t u Expl              -> par p appp $ go appp ns t . (' ':) . go projp ns u
    App t u Impl              -> par p appp $ go appp ns t . (' ':) . bracket (go letp ns u)

    Sg "_" a b                -> par p sgp $ go appp ns a . (" × "++) . go sgp (ns:>"_") b
    Sg (fresh ns -> x) a b    -> par p sgp $ piBind ns x Expl a . (" × "++) . go sgp (ns:>x) b

    Pi "_" Expl a b           -> par p pip $ go sgp ns a . (" → "++) . go pip (ns:>"_") b

    Pi (fresh ns -> x) i a b  -> par p pip $ piBind ns x i a . goPi (ns:>x) b where
                                   goPi ns (Pi (fresh ns -> x) i a b)
                                     | x /= "_" = piBind ns x i a . goPi (ns:>x) b
                                   goPi ns b = (" → "++) . go pip ns b

    Lam (fresh ns -> x) i t   -> par p letp $ ("λ "++) . lamBind x i . goLam (ns:>x) t where
                                   goLam ns (Lam (fresh ns -> x) i t) =
                                     (' ':) . lamBind x i . goLam (ns:>x) t
                                   goLam ns t =
                                     (". "++) . go letp ns t

    Let (fresh ns -> x) a t u -> par p letp $ ("let "++) . (x++) . (" : "++) . go pairp ns a
                                 . ("\n  = "++) . go pairp ns t . (";\n\n"++) . go letp (ns:>x) u

    Pair t u                  -> par p pairp $ go letp ns t . (", "++) . go pairp ns u


showTm0 :: Tm -> String
showTm0 t = prettyTm 0 [] t []
-- showTm0 = show

displayMetas :: IO ()
displayMetas = do
  ms <- readIORef mcxt
  forM_ (sortBy (comparing (weight . link . snd)) $ IM.toList ms) $ \(m, e) -> case e of
    -- Unsolved _ a -> printf "let ?%s = ?;\n"  (show m)
    -- Solved _ v a -> printf "let ?%s = %s;\n" (show m) (showTm0 $ quote 0 v)
    Unsolved _ a -> printf "let ?%s : %s = ?;\n"  (show m) (showTm0 $ quote 0 a)
    Solved _ v a -> printf "let ?%s : %s = %s;\n" (show m) (showTm0 $ quote 0 a) (showTm0 $ quote 0 v)
  putStrLn ""
