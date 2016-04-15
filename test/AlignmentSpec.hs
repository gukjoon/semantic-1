module AlignmentSpec where

import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck hiding (Fixed)
import Data.Text.Arbitrary ()

import Alignment
import ArbitraryTerm (arbitraryLeaf)
import Control.Arrow
import Control.Comonad.Cofree
import Control.Monad.Free
import Data.Bifunctor.Join
import Data.Bifunctor.These
import Data.Functor.Both as Both
import Data.Functor.Identity
import Diff
import Info
import Patch
import Prelude hiding (fst, snd)
import qualified Prelude
import Range
import Source hiding ((++), fromList)
import qualified Source
import SplitDiff
import Syntax

spec :: Spec
spec = parallel $ do
  describe "groupChildrenByLine" $ do
    it "produces symmetrical context" $
      groupChildrenByLine getRange (Join (These [Range 0 2, Range 2 4] [Range 0 2, Range 2 4])) [] `shouldBe`
        [ Join (These (Range 0 2, [] :: [SplitDiff String Info])
                      (Range 0 2, []))
        , Join (These (Range 2 4, [])
                      (Range 2 4, []))
        ]

    it "produces asymmetrical context" $
      groupChildrenByLine getRange (Join (These [Range 0 2, Range 2 4] [Range 0 1])) [] `shouldBe`
        [ Join (These (Range 0 2, [] :: [SplitDiff String Info])
                      (Range 0 1, []))
        , Join (This  (Range 2 4, []))
        ]

  describe "alignDiff" $ do
    it "aligns identical branches on a single line" $
      alignDiff (both (Source.fromList "[ foo ]") (Source.fromList "[ foo ]")) (pure (info 0 7) `branch` [ pure (info 2 5) `leaf` "foo" ]) `shouldBe`
        [ Join (These (info 0 7 `branch` [ info 2 5 `leaf` "foo" ])
                      (info 0 7 `branch` [ info 2 5 `leaf` "foo" ])) ]

    it "aligns identical branches spanning multiple lines" $
      alignDiff (both (Source.fromList "[\nfoo\n]") (Source.fromList "[\nfoo\n]")) (pure (info 0 7) `branch` [ pure (info 2 5) `leaf` "foo" ]) `shouldBe`
        [ Join (These (info 0 2 `branch` [])
                      (info 0 2 `branch` []))
        , Join (These (info 2 6 `branch` [ info 2 5 `leaf` "foo" ])
                      (info 2 6 `branch` [ info 2 5 `leaf` "foo" ]))
        , Join (These (info 6 7 `branch` [])
                      (info 6 7 `branch` []))
        ]

    it "aligns reformatted branches" $
      alignDiff (both (Source.fromList "[ foo ]") (Source.fromList "[\nfoo\n]")) (pure (info 0 7) `branch` [ pure (info 2 5) `leaf` "foo" ]) `shouldBe`
        [ Join (These (info 0 7 `branch` [ info 2 5 `leaf` "foo" ])
                      (info 0 2 `branch` []))
        , Join (That  (info 2 6 `branch` [ info 2 5 `leaf` "foo" ]))
        , Join (That  (info 6 7 `branch` []))
        ]

    it "aligns nodes following reformatted branches" $
      alignDiff (both (Source.fromList "[ foo ]\nbar\n") (Source.fromList "[\nfoo\n]\nbar\n")) (pure (info 0 12) `branch` [ pure (info 0 7) `branch` [ pure (info 2 5) `leaf` "foo" ], pure (info 8 11) `leaf` "bar" ]) `shouldBe`
        [ Join (These (info 0 8 `branch` [ info 0 7 `branch` [ info 2 5 `leaf` "foo" ] ])
                      (info 0 2 `branch` [ info 0 2 `branch` [] ]))
        , Join (That  (info 2 6 `branch` [ info 2 6 `branch` [ info 2 5 `leaf` "foo" ] ]))
        , Join (That  (info 6 8 `branch` [ info 6 7 `branch` [] ]))
        , Join (These (info 8 12 `branch` [ info 8 11 `leaf` "bar" ])
                      (info 8 12 `branch` [ info 8 11 `leaf` "bar" ]))
        , Join (These (info 12 12 `branch` [])
                      (info 12 12 `branch` []))
        ]

    it "aligns identical branches with multiple children on the same line" $
      alignDiff (pure (Source.fromList "[ foo, bar ]")) (pure (info 0 12) `branch` [ pure (info 2 5) `leaf` "foo", pure (info 7 10) `leaf` "bar" ]) `shouldBe`
        [ Join (runBothWith These (pure (info 0 12 `branch` [ info 2 5 `leaf` "foo", info 7 10 `leaf` "bar" ])) ) ]

    it "aligns insertions" $
      alignDiff (both (Source.fromList "a") (Source.fromList "a\nb")) (both (info 0 1) (info 0 3) `branch` [ pure (info 0 1) `leaf` "a", Pure (Insert (info 2 3 :< Leaf "b")) ]) `shouldBe`
        [ Join (These (info 0 1 `branch` [ info 0 1 `leaf` "a" ])
                      (info 0 2 `branch` [ info 0 1 `leaf` "a" ]))
        , Join (That (info 2 3 `branch` [ Pure (SplitInsert (info 2 3 :< Leaf "b")) ]))
        ]

    where
      isOnSingleLine (a, _, _) = filter (/= '\n') (toString a) == toString a

      combineIntoLeaves (leaves, start) char = (leaves ++ [ Free $ Annotated (Info <$> pure (Range start $ start + 1) <*> mempty <*> pure 1) (Leaf [ char ]) ], start + 1)

      leafWithRangesInSources sources ranges = Free $ Annotated (Info <$> ranges <*> pure mempty <*> pure 1) (Leaf $ runBothWith (++) (toString <$> sources))
      leafWithRangeInSource source range = Info range mempty 1 :< Leaf source

branch :: annotation -> [Free (Annotated String annotation) patch] -> Free (Annotated String annotation) patch
branch annotation = Free . Annotated annotation . Indexed

leaf :: annotation -> String -> Free (Annotated String annotation) patch
leaf info = Free . Annotated info . Leaf

info :: Int -> Int -> Info
info = ((\ r -> Info r mempty 0) .) . Range
