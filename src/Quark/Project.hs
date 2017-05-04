{-# LANGUAGE OverloadedStrings #-}

---------------------------------------------------------------
--
-- Module:      Quark.Project
-- Author:      Stefan Peterson
-- License:     MIT License
--
-- Maintainer:  Stefan Peterson (stefan.j.peterson@gmail.com)
-- Stability:   Stable
-- Portability: Unknown
--
-- ----------------------------------------------------------
--
-- Module for quark projects.
--
-- A project is a higher level container for a Flipper ExtendedBuffer with some
-- additional data.
--
---------------------------------------------------------------

module Quark.Project ( Project
                     , ProjectTree
                     , emptyProjectMeta
                     , projectRoot
                     , projectTree
                     , findDefault
                     , replaceDefault
                     , insertMode
                     , setBuffers
                     , setRoot
                     , setFindDefault
                     , setReplaceDefault
                     , setProjectTree
                     , toggleInsertMode
                     , flipNext'
                     , flipPrevious'
                     , flipTo'
                     , flipToParent'
                     , toLines
                     , assumeRoot
                     , activeP
                     , active'
                     , activePath
                     , projectTreeIndex
                     , firstF'
                     , firstTree
                     , idxOfActive'
                     , expand
                     , contract ) where

import System.FilePath ( takeDirectory
                       , takeFileName
                       , joinPath )
import Data.Bifunctor ( second )
import Data.List ( sort
                 , isPrefixOf )

import qualified Data.Text as T

import Quark.Buffer ( ExtendedBuffer )
import Quark.Flipper ( Flipper
                     , active
                     , firstF
                     , flipNext
                     , flipPrevious
                     , flipTo
                     , flipToLast
                     , toList
                     , nextEmpty
                     , previousEmpty )
import Quark.Helpers ( (~~) )
import Quark.Types ( ProjectTree
                   , ProjectTreeElement ( RootElement
                                        , FileElement
                                        , DirectoryElement ) )

data ProjectMeta = ProjectMeta { root' :: FilePath
                               , projectTree' :: ProjectTree
                               , findDefault' :: T.Text
                               , replaceDefault' :: T.Text
                               , insertMode' :: Bool } deriving Eq

type Project = (Flipper ExtendedBuffer, ProjectMeta)

----------------------------
-- Core project functions --
----------------------------

emptyProjectMeta :: ProjectMeta
emptyProjectMeta = ProjectMeta "" (RootElement "", [], []) "" "" False

projectRoot :: Project -> FilePath
projectRoot (_, projectMeta) = root' projectMeta

projectTree :: Project -> ProjectTree
projectTree (_, projectMeta) = projectTree' projectMeta

findDefault :: Project -> T.Text
findDefault (_, projectMeta) = findDefault' projectMeta

replaceDefault :: Project -> T.Text
replaceDefault (_, projectMeta) = replaceDefault' projectMeta

insertMode :: Project -> Bool
insertMode (_, projectMeta) = insertMode' projectMeta

setBuffers :: Flipper ExtendedBuffer -> Project -> Project
setBuffers buffers (_, projectMeta) = (buffers, projectMeta)

setRoot :: FilePath -> Project -> Project
setRoot s project = second (setRoot' s) project

setRoot' :: FilePath -> ProjectMeta -> ProjectMeta
setRoot' s (ProjectMeta _ a b c d) = ProjectMeta s a b c d

setFindDefault :: T.Text -> Project -> Project
setFindDefault s project = second (setFindDefault' s) project

setFindDefault' :: T.Text -> ProjectMeta -> ProjectMeta
setFindDefault' s (ProjectMeta a b _ c d) = ProjectMeta a b s c d

setReplaceDefault :: T.Text -> Project -> Project
setReplaceDefault s project = second (setReplaceDefault' s) project

setReplaceDefault' :: T.Text -> ProjectMeta -> ProjectMeta
setReplaceDefault' s (ProjectMeta a b c _ d) = ProjectMeta a b c s d

setProjectTree :: ProjectTree -> Project -> Project
setProjectTree t project = second (setProjectTree' t) project

setProjectTree' :: ProjectTree -> ProjectMeta -> ProjectMeta
setProjectTree' t (ProjectMeta a _ b c d) = ProjectMeta a t b c d

toggleInsertMode :: Project -> Project
toggleInsertMode project =
    second (setInsertMode' $ not $ insertMode project) project

setInsertMode' :: Bool -> ProjectMeta -> ProjectMeta
setInsertMode' x (ProjectMeta a b c d _) = ProjectMeta a b c d x

firstTree :: (ProjectTree -> ProjectTree) -> Project -> Project
firstTree f project = setProjectTree (f $ projectTree project) project

assumeRoot :: FilePath -> FilePath
assumeRoot = takeDirectory

activeP :: Project -> ExtendedBuffer
activeP (buffers, _) = active buffers

---------------------------
-- ProjectTree Functions --
---------------------------

active' :: ProjectTree -> ProjectTreeElement
active' t = case active t of
    DirectoryElement t' -> active' t'
    x                   -> x

projectTreeIndex :: Project -> Int
projectTreeIndex project = length prev
  where
    (_, prev, _) = projectTree project

activePath :: ProjectTree -> FilePath
activePath t = case active t of
    RootElement _       -> rootPath
    DirectoryElement t' -> activePath t'
    FileElement path    -> joinPath [rootPath, path]
  where
    (RootElement rootPath, _, _) = flipTo 0 t

idxOfActive' :: ProjectTree -> Int
idxOfActive' t = case active t of
    DirectoryElement t' -> lengthPrevious t + idxOfActive' t'
    _                   -> lengthPrevious t

lengthPrevious :: ProjectTree -> Int
lengthPrevious (_, p, _) = sum $ map length' p

length' :: ProjectTreeElement -> Int
length' (DirectoryElement t') = sum $ map length' $ toList t'
length' _                     = 1

firstF' :: (ProjectTreeElement -> ProjectTreeElement)
        -> ProjectTree -> ProjectTree
firstF' f (a, p, n) = case a of
    DirectoryElement t' -> (DirectoryElement $ firstF' f t', p, n)
    _                   -> (f a, p, n)

-- this version stops at the parent DirectoryElement of an active RootElement
firstF'' :: (ProjectTreeElement -> ProjectTreeElement)
        -> ProjectTree -> ProjectTree
firstF'' f (a, p, n) = case a of
    DirectoryElement (RootElement _, _, _) ->(f a, p, n)
    DirectoryElement t' -> (DirectoryElement $ firstF'' f t', p, n)
    _                   -> (f a, p, n)

flipNext' :: Int -> Project -> Project
flipNext' k p
    | k <= 1    = firstTree flipNext'' p
    | otherwise = flipNext' (k - 1) $ firstTree flipNext'' p

flipPrevious' :: Int -> Project -> Project
flipPrevious' k p
    | k <= 1    = firstTree flipPrevious'' p
    | otherwise = flipPrevious' (k - 1) $ firstTree flipPrevious'' p

flipTo' :: Int -> Project -> Project
flipTo' k = firstTree $ flipTo'' k

flipToParent' :: Project -> Project
flipToParent' = firstTree flipToParent''

flipNext'' :: ProjectTree -> ProjectTree
flipNext'' t@(_, _, []) = t
flipNext'' t@(a, p, n)  = case a of
    DirectoryElement t' -> if nextEmpty t'
                               then flipNext t
                               else (DirectoryElement $ flipNext'' t', p, n)
    _                   -> flipNext t

flipPrevious'' :: ProjectTree -> ProjectTree
flipPrevious'' t@(_, [], _) = t
flipPrevious'' t@(a, p, n)  = case a of
    DirectoryElement t' -> if previousEmpty t'
                               then (flipToLast''' a', p', n')
                               else (DirectoryElement $ flipPrevious'' t', p, n)
    _                   -> (flipToLast''' a', p', n')
  where
    (a', p', n') = flipPrevious t

flipTo'' :: Int -> ProjectTree -> ProjectTree
flipTo'' k t = case compare (mod k n) (lengthPrevious t) of
    EQ -> t
    LT -> flipTo'' k $ flipPrevious'' t
    _  -> flipTo'' k $ flipNext'' t
  where
    n = sum $ map length' $ toList t

flipToParent'' :: ProjectTree -> ProjectTree
flipToParent'' t@(x, y, z) = case x of
    DirectoryElement t' -> if previousEmpty t'
                               then flipTo 0 t
                               else (DirectoryElement $ flipToParent'' t', y, z)
    _                   -> flipTo 0 t

flipToLast''' :: ProjectTreeElement -> ProjectTreeElement
flipToLast''' x = case x of
    DirectoryElement (a, p, []) -> DirectoryElement (flipToLast''' a, p, [])
    DirectoryElement t          -> flipToLast''' (DirectoryElement $ flipToLast t)
    _                           -> x

expand :: [ProjectTreeElement] -> Project -> Project
expand p project = case active' $ projectTree project of
    RootElement _ -> firstTree (firstF'' (expand' p)) project
    _             -> project

expand' :: [ProjectTreeElement] -> ProjectTreeElement -> ProjectTreeElement
expand' p (DirectoryElement t) = DirectoryElement $ flipNext (r, [], sort p)
  where
    (r, _, _) = flipTo 0 t
expand' _ x                    = x

contract :: Project -> Project
contract project = case active' $ projectTree project of
    RootElement _ -> firstTree (firstF'' contract') project
    _             -> project

contract' :: ProjectTreeElement -> ProjectTreeElement
contract' (DirectoryElement t) = DirectoryElement (r, [], [])
  where
    (r, _, _) = flipTo 0 t
contract' x                    = x

toLines :: ProjectTree -> [T.Text]
toLines t = concat $ map (toLines' 0) (take k treeList) ++
                map (toLines' 1) (drop k treeList)
  where
    (treeList, k) = treeListAndSplit t

toLines' :: Int -> ProjectTreeElement -> [T.Text]
toLines' headStyle x =  case x of
    (RootElement path)   -> [T.pack (takeFileName path) ~~ "/"]
    (FileElement path)   -> [ownHead ~~ T.pack path]
    (DirectoryElement t) -> zipWith (~~) dirHead $ concat $
                                map (toLines' 2) (take k treeList) ++
                                    map (toLines' 3) (drop k treeList)
                              where
                                (treeList, k) = treeListAndSplit t
  where
    dirHead = ownHead:(repeat childHead)
    ownHead
        | headStyle == 0 = "\9567\9472"
        | headStyle == 1 = "\9561\9472"
        | headStyle == 2 = "\9564\9472"
        | otherwise      = "\9566\9472"
    childHead
        | headStyle == 0 = "\9553 "
        | headStyle == 2 = "\9474 "
        | otherwise      = "  "

treeListAndSplit :: ProjectTree -> ([ProjectTreeElement], Int)
treeListAndSplit t = (treeList, length treeList - 1)
  where
    treeList = toList t

branch :: Int -> T.Text -> T.Text -> [T.Text]
branch k own last'
    | k < 1     = []
    | k == 1    = [""]
    | otherwise = "":(replicate (k - 2) own) ++ [last']