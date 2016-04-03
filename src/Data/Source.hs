{-# LANGUAGE FlexibleInstances #-}
module Data.Source (
    -- * Core types
    Source,
    Yield (..),
    Transducer,

    -- * Source primitives
    prepend,
    complete,
    incomplete,

    -- * Transducer combinators
    mapChunk,
    whenChunk,

    -- * Utils
    drain,
    peek,
    repeat,
    replicate
  ) where

import Control.Monad
import Data.Function
import Prelude hiding ( repeat, replicate )

type Source              m c a   = m (Yield m c a)
type Transducer          m c a b = Source m c a -> Source m c b

data Yield m c a
   = Chunk a (Source m c a)
   | Complete (Source m c c -> Source m c a)
   | Incomplete (Source m c c -> Source m c a)

prepend      :: Monad m => a -> Source m c a -> Source m c a
prepend       = (pure .) . Chunk

complete     :: Applicative m => (Source m c c -> Source m c a) -> Source m c a
complete      = pure . Complete

incomplete   :: Applicative m => (Source m c c -> Source m c a) -> Source m c a
incomplete    = pure . Incomplete

drain        :: Monad m => Source m c a -> m ()
drain         = let f (Chunk _ src) = drain src
                    f _             = pure ()
                in  (=<<) f

peek         :: Monad m => Source m c a -> Source m c a
peek          = let f (Chunk a sa) = Chunk a $ prepend a sa
                    f ya           = ya
                in  fmap f

repeat       :: Monad m => a -> Source m c a
repeat      a = pure $ Chunk a $ repeat a

replicate    :: (Monad m, Integral i) => i -> a -> Source m a a
replicate 0 _ = pure $ Complete id
replicate i a = pure $ Chunk a $ replicate (pred i) a

instance Monad m => Monoid (Yield m a a) where
  mempty                      = Complete id
  Chunk a sa   `mappend`   yb = Chunk a (f sa)
    where
      f sc = sc >>= \yc-> pure $ case yc of
        Chunk d sd   -> Chunk d (f sd)
        Complete _   -> yb
        Incomplete _ -> yb
  Complete _   `mappend`   yb = yb
  Incomplete _ `mappend`   yb = yb

instance Monad m => Functor (Yield m c) where
  fmap f (Chunk a src)            = Chunk     (f a) (fmap f <$> src)
  fmap f (Complete g)             = Complete   (\c-> fmap f <$> g c)
  fmap f (Incomplete g)           = Incomplete (\c-> fmap f <$> g c)

instance Monad m => Applicative (Yield m c) where
  pure                          a = fix $ Chunk a . pure
  Chunk f sf    <*>    Chunk a sa = Chunk (f a) $ sf >>= \g-> liftM (g <*>) sa
  Complete ca   <*>            yb = Complete   $ ca >=> pure . (<*> yb)
  ya            <*>   Complete cb = Complete   $ cb >=> pure . (ya <*>)
  Incomplete ca <*>            yb = Incomplete $ ca >=> pure . (<*> yb)
  ya            <*> Incomplete cb = Incomplete $ cb >=> pure . (ya <*>)

mapChunk :: Functor m => (a -> Source m c a -> Yield m c b) -> Transducer m c a b
mapChunk f = fmap g
  where
    g (Chunk a sa)   = f a sa
    g (Complete h)   = Complete   $ mapChunk f . h
    g (Incomplete h) = Incomplete $ mapChunk f . h

whenChunk :: Monad m => (a -> Source m c a -> Source m c b) -> Transducer m c a b
whenChunk f = (=<<) g
  where
    g (Chunk a sa)   = f a sa
    g (Complete h)   = pure $ Complete   $ whenChunk f . h
    g (Incomplete h) = pure $ Incomplete $ whenChunk f . h
