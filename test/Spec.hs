{-# LANGUAGE OverloadedStrings #-}

import           Control.Concurrent         (threadDelay)
import           Data.ByteString.Lazy.Char8          (unpack)
import           Control.Concurrent.Async
import           Lib
import           Network.HTTP
import           Server
import           Test.Tasty
import           Test.Tasty.HUnit
import           Data.Aeson

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Tests" [unitTests, integrationTests]

unitTests :: TestTree
unitTests =
  testGroup "Unit tests" [testCase "valid chain" testValidChain]

integrationTests :: TestTree
integrationTests =
  testGroup "Integration Test" [testCase "valid chain" testBasicSync]

testValidChain :: IO ()
testValidChain = do
  let b = initialBlock
  assertBool "block eq" $ b == b
  assertBool "empty chains are valid" $ isValidChain []
  assertBool "base chain is valid" $ isValidChain [b]
  assertBool "two init blocks are invalid" $ not $ isValidChain [b, b]
  goodBlock <- mineBlockFrom b "asdfasdf"
  assertBool "actually good chain" $ isValidChain [b, goodBlock]

testBasicSync :: IO ()
testBasicSync =
  let webPorts = ["8001", "8002"]
      p2pPorts = ["9001", "9002"]
      args = MainArgs (head webPorts) (head p2pPorts) Nothing
      args' =
        MainArgs (last webPorts) (last p2pPorts) $
        Just ("localhost:" ++ head p2pPorts)
  in do _ <- async $ runLegion args
        _ <- async $ runLegion args'
        -- wait to let the servers initialize
        threadDelay 3000000
        _ <- allChainsHaveLength webPorts 1
        let blockArgs = unpack . encode $ BlockArgs "some data"
        print blockArgs
        _ <-
          simpleHTTP
            (postRequestWithBody
               "http://127.0.0.1:8001/block"
               "application/json"
               blockArgs) >>=
          fmap (take 10000) . getResponseBody
        threadDelay 1000000
        _ <- allChainsHaveLength webPorts 2
        _ <-
          simpleHTTP
            (postRequestWithBody
               "http://127.0.0.1:8002/block"
               "application/json"
               blockArgs)
        threadDelay 1000000
        _ <- allChainsHaveLength webPorts 3
        return ()

allChainsHaveLength :: [String] -> Int -> IO ()
allChainsHaveLength ports len = do
  lengths <- mapM getChainLength ports
  assertBool ("all have length " ++ show len) $ all (== len) lengths

getChainLength :: String -> IO Int
getChainLength serverPort = do
  body <-
    simpleHTTP (getRequest ("http://127.0.0.1:" ++ serverPort ++ "/chain")) >>=
    fmap (take 10000) . getResponseBody
  let parsedBody = read body :: [Block]
  print parsedBody
  return $ length parsedBody
