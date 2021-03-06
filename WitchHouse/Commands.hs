{-# LANGUAGE BangPatterns #-}
module WitchHouse.Commands
( parseCommand
) where

import WitchHouse.World
import WitchHouse.Types
import WitchHouse.Wisp
import qualified Data.Map as M
import System.IO
import Control.Monad ((>=>))
import Prelude hiding (take, drop)
import Data.ByteString.Char8 (pack)
import Data.List ((\\))
import System.IO.Unsafe

import Text.ParserCombinators.Parsec
import Control.Applicative hiding ((<|>), many, optional)


type Command = World -> IO World

-- | Parse an input string into a command using the given
-- command map.
parseCommand :: String -> Command
parseCommand s = case parse command "" s of
  Left e -> notify (show e)-- notify $ "I don't know what `" ++ s ++ "' means."
  Right c -> c

{- NOTIFICATION HELPERS -}

tryTo :: (World -> Either String World) -> (World -> World -> IO World) -> Command
tryTo t s w = case t w of
  Left err -> notify err w
  Right w' -> s w w'

{- COMMANDS -}

help :: Command
help = notify helpMsg
  where
    helpMsg = unlines $
      [ "In the following examples, angle brackets (`<' and `>') denote required arguments,"
      , "and square brackets (`[' and `]') denote optional arguments."
      , "A superset of these commands is available:"
      , ""
      , "basic commands:"
      , "  look"
      , "  go        <direction>"
      , "  take      <thing>"
      , "  drop      <thing>"
      , "  enter     <thing>"
      , "  exit"
      , "  say       [message]"
      , "  /me       [whatever it is that you do]"
      , "  help"
      , "  whoami"
      , ""
      , "building commands:"
      , "  make     <thing> ;; make a new object with the given name. it will appear"
      , "                   ;; in your inventory."
      , "  link     <origin> <destination> <direction>"
      , "  unlink   <origin> <direction>"
      , "  recycle  <thing>"
      , ""
      , "lisp interaction:"
      , "  <s-expression> ;; eval the expression"
      , "  @<target> <s-expression> ;; evaluate lisp in the target's context. you must"
      , "                           ;; have a ref to the target in your *refs* binding."
      , "  bindings ;; list current bindings in your environment"
      , "  reset    ;; reset your environment. use with caution!"
      , "  share <binding> <target>"

      , ""
      , "Entering a nullary command not listed here will attempt to call the lisp function"
      , "of the same name (if present in your environment). Note that several basic commands"
      , " are implemented in lisp, so *override them at your own risk*. You can use the "
      , "`reset' command to restore your environment if it becomes corrupted."
      ]

send :: String -> Command
send actn w = do
  res <- invoke actn [Wd w] w
  case res of Left err -> notify err w
              Right (Wd w') -> return w'
              Right _ -> return w

send2 op targ = tryTo (find (matchName targ) Location) $ \w w' -> do
  res <- invoke op [Wd w] w'
  case res of Left err -> notify err w
              Right (Wd w'') -> return w''
              Right _ -> return w

bindings :: Command
bindings w = do
  (m,_) <- getFrame (objId $ focus w)
  notify (show m) w


quit :: Command
quit w@(f,_) = case handle f of
  Nothing -> return w
  Just h -> do hPutStrLn h "Bye!" >> hClose h
               unbind (objId f) (pack "*handle*")
               return w

goes :: String -> Command
goes dir = tryTo (go dir) $ \w w' -> do
  notifyExcept ((name $ focus w) ++ " goes " ++ dir ++ ".") w
  notifyExcept ((name $ focus w) ++ " arrives.") w'
  send "look" w'

enters :: String -> Command
enters n = tryTo (enter $ matchName n) $ \w w' -> do
  (++ " enters "++(name . focus . zUp' $ w')++".") . name . focus >>= notifyExcept $ w
  send "look" w'
  ((++" enters.") . name . focus >>= notifyExcept) w'

makes :: String -> Command
makes n w = do
  w' <- make n w
  addRef w (objId $ focus w')
  notify ("You make "++n++".") w
  return w'

addRef :: World -> Int -> IO ()
addRef (Obj{objId = f},_) i = do
  let refsym = pack "*refs*"
  (bs,_) <- getFrame f
  bind f refsym $ case M.lookup refsym bs of
    Just (Lst l) -> Lst $ (Ref i):l
    _              -> Lst [Ref i]

addBind :: World -> Val -> IO ()
addBind (Obj{objId = f},_) v = do
  let bindsym = pack "*shared-bindings*"
  (bs,_) <- getFrame f
  bind f bindsym $ case M.lookup bindsym bs of
    Just (Lst l) -> Lst $ v:l
    _              -> Lst [v]

hasRef :: World -> World -> Bool
(Obj{objId = f1},_) `hasRef` (Obj{objId = f2},_) = unsafePerformIO $ do
  (bs,_) <- getFrame f1
  case M.lookup (pack "*refs*") bs of
    Just (Lst l) -> return $ Ref f2 `elem` l
    _ -> return False

shareBinding :: String -> String -> Command
shareBinding b t = tryTo (find (matchName t) Location) $ \w t' -> do
  (bs,_) <- getFrame (objId $ focus w)
  case M.lookup (pack b) bs of
    Nothing -> notify ("You don't have a binding called " ++ b ++ ".") w
    Just v -> do addBind t' v
                 notify "Binding shared!" w
                 notify (name (focus w) ++ " has shared a binding with you!") t'

recycle :: String -> Command
recycle n = tryTo (find (matchName n) Self) $ \w w' ->
  case handle . focus $ w' of
    Just _ -> notify "You can't recycle an active player!" w >> notify ((name . focus $ w) ++ " tried to recycle you!") w'
    Nothing -> case contents . focus $ w' of
                 [] -> do notify ((name $ focus w') ++ " has been recycled.") w
                          dropFrame . objId $ focus w'
                          return $ zDel w'
                 _ -> notify "You can't recycle a non-empty object." w

reset :: Command
reset w@((Obj{objId = f}),_) = do
  (bs,_) <- getFrame f
  let defs = M.keys bs \\ [pack "*name*", pack "*desc*", pack "*password*", pack "*handle*"]
  mapM_ (unbind f) defs
  notify "Bindings reset." w

links :: String -> String -> Command
links dir dest = tryTo (zUp >=> link dir (matchName dest)) $ \w w' -> do
  let w'' = find' (== focus w) Self w'
  notify ("Linked: "++dir++" => "++dest) w''

unlinks :: String -> Command
unlinks dir = tryTo (zUp >=> unlink dir) $ \w w' -> do
  let w'' = find' (focus w==) Self w'
  notify ("Unlinked: " ++ dir) w''

say :: String -> Command
say msg = notify ("You say \""++msg++"\"") >=> ((++" says \""++msg++"\"") . name . focus >>= notifyExcept)

me :: String -> Command
me msg = notify msg >=> notifyExcept msg

evals :: String -> Command
evals s w = s `evalOn` w >>= \res -> case res of
  Left err -> notify err w
  Right v -> notify (show v) w >> return w

evalIn :: String -> String -> Command
evalIn l t = tryTo (find (matchName t) Location) $ \w t' ->
  if w `hasRef` t' then evals l t' else notify "You aren't allowed to do that." w

takes :: String -> Command
takes n = tryTo (take $ matchName n) $ \w w' -> do
  notify ("You take " ++ (name $ focus w') ++ ".") w
  notifyExcept ((name $ focus w) ++ " takes " ++ (name $ focus w')) (zUp' w')
  notify ((name $ focus w) ++ " takes you!") w'

drops :: String -> Command
drops n = tryTo (drop $ matchName n) $ \w w' -> do
  notify ("You drop " ++ (name $ focus w') ++ ".") w               
  notifyExcept ((name $ focus w) ++ " drops " ++ (name $ focus w')) w
  invoke "looks" [Wd w'] w'
  notify ((name $ focus w) ++ " drops you!") w'



command :: GenParser Char st Command
command = optional whitespace *> (wispExpr <|> targetedExpr <|> cmd)

  where
    whitespace = many1 $ oneOf " \n\r\t"

    wispExpr = evals `fmap` ((:) <$> char '(' <*> many anyChar)

    targetedExpr = do
      char '@'
      target <- str
      expr <- many anyChar
      return $ evalIn expr target

    eof' = optional whitespace <* eof

    unary s   = try $ string s *> whitespace *> str <* eof'
    nullary s = try $ string s <* eof'
    binary s  = try $ do
      string s
      whitespace
      s1 <- str
      s2 <- str
      eof'
      return (s1,s2)


    stringQuotedBy c = char c *> many cs <* char c
      where cs = try (string ['\\',c] >> return c) <|> noneOf [c]

    str =  stringQuotedBy '\''
       <|> stringQuotedBy '\"'
       <|> stringQuotedBy '`'
       <|> (many (noneOf " \n\r\t") <* optional whitespace)


    cmd =  cEnter
       <|> cGo
       <|> cMake
       <|> cTake
       <|> cDrop
       <|> cQuit
       <|> cLink
       <|> cUnlink
       <|> cSay
       <|> cEmote
       <|> cReset
       <|> cRecycle
       <|> cBindings
       <|> cHelp
       <|> cShare
       <|> cSend
       <|> cSend2

    cEnter    = enters `fmap` unary "enter"
    cGo       = goes `fmap` unary "go"
    cMake     = makes `fmap` unary "make"
    cTake     = takes `fmap` unary "take"
    cDrop     = drops `fmap` unary "drop"
    cQuit     = nullary "quit" >> return quit
    cLink     = binary "link" >>= \(dir,dest) -> return $ links dir dest
    cShare    = binary "share" >>= \(b,t) -> return $ shareBinding b t
    cUnlink   = unlinks `fmap` unary "unlink"
    cSay      = say `fmap` try (string "say" *> whitespace *> many1 anyChar)
    cEmote    = me `fmap` try (string "\\me" *> whitespace *> many1 anyChar)
    cReset    = nullary "reset" >> return reset
    cRecycle  = recycle `fmap` unary "recycle"
    cBindings = nullary "bindings" >> return bindings
    cHelp     = nullary "help" >> return help
    cSend     = try (str <* eof) >>= return . send
    cSend2    = do
      s1 <- str
      s2 <- str
      eof
      return $ send2 s1 s2

