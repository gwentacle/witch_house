{-# LANGUAGE TupleSections #-}
module Gretel.Command.Commands
( rootMap
, huh
) where

import Prelude hiding (take, drop)
import Gretel.World
import Gretel.Command.Types
import Gretel.Command.Response
import Data.Maybe
import qualified Data.Map as M
import qualified Data.Set as S
import Data.List (intercalate, delete)

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
  ]

huh :: WorldTransformer Response
huh = (self "Huh?",)

exits :: Command
exits n [] w = let es = M.keys . edges $ locOf n w
                   ms = "The following exits are available:":es
                   msg = intercalate "\n" ms
  in (self msg,w)
exits _ _ w = huh w

go :: Command
go n [dir] w = case n `goes` dir $ w of
  (False,w') -> (self "You can't go that way!",w')
  (True, w') -> (local (desc (locOf n w) [n]) (n++" arrives.")
                , w')
go _ [] w = (self "Go where?",w)
go _ _ w = huh w

unlink :: Command
unlink _ [n,dir] w = case n `deadends` dir $ w of
  (False,w') -> huh w'
  (True,w')  -> (self "",w')
unlink _ _ w = huh w

take :: Command
take n [t] w = case n `takes` t $ w of
  (False,w') -> (self $ "There's no " ++ t ++ " here."
                , w')
  (True, w') -> (local ("You now have a " ++ t ++ ".") (n ++ " picks up " ++ t)
                , w')
take _ [] w = (self "Take what?",w)
take _ _ w = huh w

exit :: Command
exit n [] w = case n `leaves` (name $ locOf n w) $ w of
  (False,w') -> (self "You can't exit your current location.",w')
  (True,w')  -> look n [] w'
exit _ _ w = huh w

look :: Command
look n [] w = (self $ desc (locOf n w) [n],w)
look n [dir] w = let loc = locOf n w
                     txt = do d <- dir `from` loc
                              dest <- M.lookup d w
                              return $ desc dest []
  in case txt of
    Nothing -> (self "You don't see anything in that direction."
               , w)
    Just d  -> (self d, w)
look _ _ w  = huh w

make :: Command
make n [o] w = case n `makes` o $ w of
  (False,w')  -> (self $ o ++ " already exists!", w')
  (True,w') -> (local ("You've created " ++ o ++ ".") (n++" creates "++o++".")
               , w')
make _ _ w = huh w

enter :: Command
enter n [o] w = case n `enters` o $ w of
  (False,w') -> (self $ "You can't enter "++o++"."
                , w')
  (True,w')  -> (local (desc (locOf n w) [n]) (n++" enters from somewhere beyond...")
                , w')
enter _ [] w = (self "Enter where?",w)
enter _ _ w = huh w

drop :: Command
drop n [o] w = case n `drops` o $ w of
  (False,w') -> (self "You can't drop what you don't have!",w')
  (True,w')  -> (local ("You drop " ++ o ++ ".") (n++" drops "++o++".")
                , w')
drop _ _ w = huh w

link :: Command
link _ [n1,n2,d] w = case (n1 `adjoins` n2) d w of
  (False,w') -> (self "You can't link those rooms!",w')
  (True,w')  -> (self "",w')
link _ _ w = huh w

describe :: Command
describe _ [o,d] w = case (d `describes` o) w of
  (False,w') -> huh w'
  (True,w')  -> (self "",w')
describe _ _ w = huh w

examine :: Command
examine n [t] w = case find2 n t w of
  Nothing -> huh w
  Just (n1,n2) -> if location n1 == location n2
                  then (self $ desc n2 [],w)
                  else (self $ "You see no "++t++" here.",w)
examine _ [] w = (self "Examine what?",w)
examine _ _ w = huh w

-- helper fns

locOf :: Name -> World -> Node
locOf n w = let n' = w M.! n in  w M.! (fromJust $ location n')

desc :: Node -> [Name] -> String
desc n xs = let cs = S.toList $ contents n S.\\ S.fromList xs
                ps = map (++ " is here.") cs
                dv = replicate (length $ name n) '-'
  in intercalate "\n" . delete "" $
    [ name n
    , dv
    , description n
    , dv
    ] ++ ps

