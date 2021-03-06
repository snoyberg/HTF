{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -F -pgmF ./dist/build/htfpp/htfpp #-}
--
-- Copyright (c) 2005,2010   Stefan Wehr - http://www.stefanwehr.de
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License as
-- published by the Free Software Foundation; either version 2 of
-- the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
-- General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
-- 02111-1307, USA.
--

import Test.Framework
import Test.Framework.TestManager
import Test.Framework.BlackBoxTest

import System.Environment
import System.Directory
import System.FilePath
import System.Process
import System.Exit
import System.IO
import System.IO.Temp
import Control.Exception
import Control.Monad
import qualified Data.HashMap.Strict as M
import qualified Data.Aeson as J
import Data.Aeson ( (.=) )
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as BSLC
import Data.Maybe
import qualified Data.Text as T
import qualified Text.Regex as R
import {-@ HTF_TESTS @-} qualified TestHTFHunitBackwardsCompatible
import {-@ HTF_TESTS @-} qualified Foo.A as A
import {-@ HTF_TESTS @-} Foo.B

data T = A | B
       deriving Eq

{-
stringGap = "hello \
            \world!"
-}
stringGap = "hello world!"

handleExc :: a -> SomeException -> a
handleExc x _ = x

test_assertFailure =
    assertFailure "I'm a failure"

test_stringGap = assertEqual stringGap "hello world!"

test_assertEqual = assertEqual 1 2

test_assertEqualV = assertEqualVerbose "blub" 1 2

test_assertEqualNoShow = withOptions (\opts -> opts { to_parallel = False }) $
                         assertEqualNoShow A B

test_assertListsEqualAsSets = assertListsEqualAsSets [1,2] [2]

test_assertSetEqualSuccess = assertListsEqualAsSets [1,2] [2,1]

test_assertNotEmpty = assertNotEmpty []

test_assertEmpty = assertEmpty [1]

test_assertThrows = assertThrows (return () :: IO ()) (handleExc True)

test_assertThrows' = assertThrows (error "ERROR") (handleExc False)

test_assertThrowsIO1 = assertThrows (fail "ERROR" :: IO ()) (handleExc False)

test_assertThrowsIO2 = assertThrowsIO (fail "ERROR") (handleExc True)

test_someError = error "Bart Simpson!!" :: IO ()

test_pendingTest = unitTestPending "This test is pending"

test_subAssert = subAssert anotherSub
    where
      anotherSub = subAssertVerbose "I'm another sub" (assertNegative 42)
      assertNegative n = assertBool (n < 0)

data Expr = PlusExpr Expr Expr
          | MultExpr Expr Expr
          | Literal Int
          | Variable String
            deriving (Eq, Show)

test_diff =
    assertEqual (mkExpr 1) (mkExpr 2)
    where
      mkExpr i =
          PlusExpr (PlusExpr (MultExpr (PlusExpr (Variable "foo")
                                                     (MultExpr (Literal 42) (Variable "bar")))
                                       (PlusExpr (Literal i) (Literal 2)))
                             (Literal 581))
                   (Variable "egg")

prop_ok :: [Int] -> Property
prop_ok xs = classify (null xs) "trivial" $ xs == (reverse (reverse xs))

prop_fail :: [Int] -> Bool
prop_fail xs = xs == (reverse xs)

prop_pendingProp :: Int -> Bool
prop_pendingProp x = qcPending "This property is pending" (x == 0)

prop_exhaust = False ==> True

prop_error :: Bool
prop_error = error "Lisa"

changeArgs args = args { maxSuccess = 1 }

prop_ok' = withQCArgs (\a -> a { maxSuccess = 1}) $
                     \xs -> classify (null xs) "trivial" $
                            (xs::[Int]) == (reverse (reverse xs))

prop_fail' =
    withQCArgs (\a -> a { replay = read "Just (1292732529 652912053,3)" }) prop
    where prop xs = xs == (reverse xs)
              where types = xs::[Int]

prop_error' :: TestableWithQCArgs
prop_error' = withQCArgs changeArgs $ (error "Lisa" :: Bool)

checkOutput output =
    do bsl <- BSL.readFile output
       let jsons = map (fromJust . J.decode) (splitJson bsl)
       check jsons (J.object ["type" .= J.String "test-results"])
                   (J.object ["failures" .= J.toJSON (30::Int)
                             ,"passed" .= J.toJSON (12::Int)
                             ,"pending" .= J.toJSON (2::Int)
                             ,"errors" .= J.toJSON (1::Int)])
       check jsons (J.object ["type" .= J.String "test-end"
                             ,"test" .= J.object ["flatName" .= J.String "Main:diff"]])
                   (J.object ["test" .= J.object ["location" .= J.object ["file" .= J.String "TestHTF.hs$"
                                                                         ,"line" .= J.toJSON (103::Int)]]
                             ,"location" .= J.object ["file" .= J.String "TestHTF.hs$"
                                                     ,"line" .= J.toJSON (104::Int)]])
       check jsons (J.object ["type" .= J.String "test-end"
                             ,"test" .= J.object ["flatName" .= J.String "Foo.A:a"]])
                   (J.object ["test" .= J.object ["location" .= J.object ["file" .= J.String "Foo/A.hs$"
                                                                         ,"line" .= J.toJSON (10::Int)]]
                             ,"location" .= J.object ["file" .= J.String "./Foo/A.hs"
                                                     ,"line" .= J.toJSON (11::Int)]])
       check jsons (J.object ["type" .= J.String "test-end"
                             ,"test" .= J.object ["flatName" .= J.String "Main:subAssert"]])
                   (J.object ["callers" .= J.toJSON [J.object ["message" .= J.Null
                                                              ,"location" .= J.object ["file" .= J.String "TestHTF.hs$"
                                                                                      ,"line" .= J.toJSON (92::Int)]]
                                                    ,J.object ["message" .= J.String "I'm another sub"
                                                              ,"location" .= J.object ["file" .= J.String "TestHTF.hs$"
                                                                                      ,"line" .= J.toJSON (94::Int)]]]])
    where
      check jsons pred assert =
          case filter (\j -> matches j pred) jsons of
            [json] ->
                if not (matches json assert)
                   then error ("Predicate " ++ show pred ++ " match JSON " ++ show json ++ ", but assertion " ++
                               show assert ++ " not satisfied")
                   else return ()
            l -> error ("not exactly one JSON matches predicate " ++ show pred ++ " but " ++ show l)
      matches :: J.Value -> J.Value -> Bool
      matches json pred =
          case (json, pred) of
            (J.Object objJson, J.Object objPred) ->
                M.foldrWithKey (\k vPred b ->
                                    b && case M.lookup k objJson of
                                           Just vJson -> matches vJson vPred
                                           Nothing -> False)
                               True objPred
            (J.String strJson, J.String strPred) ->
                regexMatches (mkRegex strPred) strJson
            (arrJson@(J.Array _), arrPred@(J.Array _)) ->
                let J.Success (listJson :: [J.Value]) = J.fromJSON arrJson
                    J.Success (listPred :: [J.Value]) = J.fromJSON arrPred
                in length listJson == length listPred &&
                   all (\(x, y) -> matches x y) (zip listJson listPred)
            _ -> json == pred
      regexMatches r s = isJust $ R.matchRegex r (T.unpack s)
      mkRegex s = R.mkRegexWithOpts (T.unpack s) True False
      splitJson bsl =
          if BSL.null bsl
             then []
             else case BSL.span (/= 10) bsl of
                    (start, rest) ->
                        if BSLC.pack "\n;;\n" `BSL.isPrefixOf` rest
                           then start : splitJson (BSL.drop 4 rest)
                           else case splitJson rest of
                                  [] -> error "invalid json output from HTF"
                                  (x:xs) -> (start `BSL.append` x : xs)

main =
    do args <- getArgs
       b <- doesDirectoryExist "tests/bbt"
       let dirPrefix = if b then "tests" else ""
       bbts <- blackBoxTests (dirPrefix </> "bbt") (dirPrefix </> "./run-bbt.sh") ".x"
                 (defaultBBTArgs { bbtArgs_verbose = False })
       let tests = [addToTestSuite htf_thisModulesTests bbts] ++ htf_importedTests
       when ("--help" `elem` args || "-h" `elem` args) $
            do hPutStrLn stderr ("USGAGE: dist/build/test/test [--direct]")
               ecode <- runTestWithArgs ["--help"] ([] :: [Test])
               exitWith ecode
       case args of
         "--direct":rest ->
             do ecode <- runTestWithArgs rest tests
                case ecode of
                  ExitFailure _ -> return ()
                  _ -> fail ("unexpected exit code: " ++ show ecode)
         _ ->
             do withSystemTempFile "HTF-out" $ \outFile h ->
                  do hClose h
                     ecode <- runTestWithArgs ["-j4", "--deterministic",
                                               "--json", "--output-file=" ++ outFile] tests
                     case ecode of
                       ExitFailure _ -> checkOutput outFile
                       _ -> fail ("unexpected exit code: " ++ show ecode)
                     `onException` (do s <- readFile outFile
                                       hPutStrLn stderr s)
                ecode <- system (dirPrefix </> "compile-errors/run-tests.sh")
                exitWith ecode
