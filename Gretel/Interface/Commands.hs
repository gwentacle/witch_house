{-# LANGUAGE TupleSections #-}
module Gretel.Interface.Commands
( rootMap
, huh
) where

import Prelude hiding (take, drop)
import Gretel.World
import Gretel.Interface.Types
import Data.Maybe
import qualified Data.Map as M
import Data.List hiding (take, drop)

rootMap :: CommandMap
rootMap = M.fromList $
  [ ("go", go)
  , ("take", take)
  , ("look", look)
  , ("make", make)
  , ("drop", drop)
  , ("link", link)
  , ("unlink", unlink)
  , ("enter", enter)
  , ("exit", exit)
  , ("describe", describe)
  , ("examine", examine)
  , ("exits", exits)
  , ("say", say)
  , ("/me", me)
  , ("help", help)
  ]

notifyAll :: String -> String -> World -> [Notification]
notifyAll r msg = map (\n -> Notify n msg) . fromJust . contents r

notify1 :: String -> String -> [Notification]
notify1 n m = [Notify n m]

notifyAllBut :: String -> String -> String -> World -> [Notification]
notifyAllBut n r msg = map (\p -> Notify p msg) . filter (n/=) . fromJust .contents r

help :: Command
help n _ w = (notify1 n helpMsg,w)
  where
    helpMsg = unlines $ [
        "A superset of these commands is available:"
      , "  look     [direction]"
      , "  exits"
      , "  go       <direction>"
      , "  take     <object>"
      , "  drop     <object>"
      , "  enter    <object>"
      , "  exit"
      , "  examine  <object>"
      , "  make     <object>"
      , "  link     <origin> <destination> <direction>"
      , "  unlink   <origin> <direction>"
      , "  describe <object>"
      , "  say      [message]"
      , "  /me      [whatever it is that you do]"
      , "  help"
      ]


huh :: String -> WorldTransformer [Notification]
huh n = (notify1 n "Huh?" ,)

say :: Command
say n s w = let msg = n ++ "says, \"" ++ unwords s ++ "\""
  in (notifyAll (fromJust $ getLoc n w) msg w,w)

me :: Command
me n s w = let msg = n ++ " " ++ unwords s
  in (notifyAll (fromJust $ getLoc n w) msg w,w)


exits :: Command
exits n [] w = let es = map fst . fromJust $ exitsFor n w
                   ms = "The following exits are available:":es
                   msg = intercalate "\n" ms
  in (notify1 n msg,w)
exits n _ w = huh n w

go :: Command
go n [dir] w = case n `goes` dir $ w of
  (False,w') -> (notify1 n "You can't go that way!",w')
  (True, w') -> ( notify1 n (desc (fromJust $ getLoc n w') w' [n]) ++ 
                  notifyAllBut n (fromJust $ getLoc n w') (n++" arrives from "++ (fromJust $ getLoc n w) ++ ".") w' ++ 
                  notifyAllBut n (fromJust $ getLoc n w) (n++" goes "++dir++".") w'
                , w')

go n [] w = (notify1 n "Go where?",w)
go n _ w = huh n w

unlink :: Command
unlink _ [n,dir] w = case n `deadends` dir $ w of
  (False,w') -> huh n w'
  (True,w')  -> ([Notify n ""],w')
unlink n _ w = huh n w

take :: Command
take n [t] w = case n `takes` t $ w of
  (False,w') -> (notify1 n $ "There's no " ++ t ++ " here."
                , w')
  (True, w') -> ((Notify n $ "You now have a " ++ t ++ "."):(notifyAllBut n (fromJust $ getLoc n w') (n ++ " picks up " ++ t) w')
                , w')
take n [] w = (notify1 n $ "Take what?",w)
take n _ w = huh n w

exit :: Command
exit n [] w = case n `leaves` orig $ w of
  (False,w') -> (notify1 n $ "You can't exit your current location.",w')
  (True,w')  -> let dest = fromJust $ getLoc n w'
                in ( notify1 n (desc dest w [n]) ++
                     notifyAllBut n dest (n++" arrives from "++orig++".") w' ++
                     notifyAllBut n orig (n++" exits to "++dest++".") w'
                   , w')
  where orig = fromJust $ getLoc n w
                 
exit n _ w = huh n w

look :: Command
look n [] w = (notify1 n $ desc (fromJust $ getLoc n w) w [n],w)
look n [dir] w = let loc = fromJust $ getLoc n w
                     txt = do d <- dir `from` loc $ w
                              return $ desc d w []
  in case txt of
    Nothing -> (notify1 n "You don't see anything in that direction."
               , w)
    Just d  -> (notify1 n d, w)
look n _ w  = huh n w

make :: Command
make n [o] w = case n `makes` o $ w of
  (False,w')  -> (notify1 n $ o ++ " already exists!", w')
  (True,w') -> ((Notify n $ "You've created " ++ o ++ "."):(notifyAllBut n (fromJust $ getLoc n w') (n++" creates "++o++".") w')
               , w')
make n _ w = huh n w

enter :: Command
enter n [o] w = case n `enters` o $ w of
  (False,w') -> (notify1 n $ "You can't enter "++o++"."
                , w')
  (True,w')  -> let ol = fromJust $ getLoc n w
                    nl = fromJust $ getLoc n w'
    in ( notify1 n (desc nl w' [n]) ++
         notifyAllBut n nl (n++" enters from "++ol++".") w' ++
         notifyAllBut n ol (n++" enters "++o++".") w'
       , w')
enter n [] w = (notify1 n "Enter where?",w)
enter n _ w = huh n w

drop :: Command
drop n [o] w = case n `drops` o $ w of
  (False,w') -> (notify1 n "You can't drop what you don't have!",w')
  (True,w')  -> ( notify1 n ("You drop " ++ o ++ ".") ++
                  notifyAllBut n (fromJust $ getLoc n w') (n++" drops "++o++".") w'
                , w')
drop n _ w = huh n w

link :: Command
link n [n1,n2,d] w = case (n1 `adjoins` n2) d w of
  (False,w') -> (notify1 n "You can't link those rooms!" ,w')
  (True,w')  -> ([],w')
link n _ w = huh n w

describe :: Command
describe n [o,d] w = case (d `describes` o) w of
  (False,w') -> huh n w'
  (True,w')  -> ([],w')
describe n _ w = huh n w

examine :: Command
examine n [t] w
  | hasKey n w && hasKey t w = if getLoc n w == getLoc t w
    then (notify1 n $ desc t w [],w)
    else (notify1 n $ "You see no "++t++" here.",w)
  | otherwise = huh n w
examine n [] w = (notify1 n "Examine what?",w)
examine n _ w = huh n w

-- helper fns

desc :: String -> World -> [String] -> String
desc n w xs = let cs = fromJust (contents n w) \\ xs
                  ps = map (++ " is here.") cs
                  dv = replicate (length . fromJust $ getName n w) '-'
  in intercalate "\n" . delete "" $
    [ n
    , dv
    , fromJust $ getDesc n w
    , dv
    ] ++ ps

