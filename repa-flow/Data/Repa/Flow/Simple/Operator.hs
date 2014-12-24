
module Data.Repa.Flow.Simple.Operator
        ( repeat_i
        , replicate_i
        , map_i,        map_o
        , dup_oo,       dup_io,         dup_oi
        , connect_i)

{-
        , head_i
        , peek_i
        , pre_i
        , groups_i
        , pack_ii
        , folds_ii
        , watch_i
        , watch_o
        , trigger_o
        , discard_o
        , ignore_o
-}
where
import Data.Repa.Flow.Simple.Base
import Control.Monad
import Data.Repa.Flow.Generic                   (States(..))
import qualified Data.Repa.Flow.Generic         as G

{-
import Data.Repa.Flow.Simple.List
import Data.Repa.Flow.Simple.Base
import Control.Monad
import Prelude          hiding (length)
import GHC.Exts         hiding (toList)
import qualified Prelude        as P
-}

-- Constructors ---------------------------------------------------------------
-- | Produce an flow that always produces the same value.
repeat_i :: Monad m => a -> m (Source m a)
repeat_i x
        = liftM wrap $ G.repeat_i () (const x)
{-# INLINE [2] repeat_i #-}


-- | Produce a flow of the given length that always produces the same value.
replicate_i 
        :: States () m Int
        => Int -> a -> m (Source m a)
replicate_i n x 
        = liftM wrap $ G.replicate_i () n (const x)
{-# INLINE [2] replicate_i #-}


-- Mapping --------------------------------------------------------------------
map_i     :: Monad m => (a -> b) -> Source m a -> m (Source m b)
map_i f s = liftM wrap $ G.map_i (\() x -> f x) $ unwrap s

map_o     :: Monad m => (a -> b) -> Sink   m b -> m (Sink   m a)
map_o f s = liftM wrap $ G.map_o (\() x -> f x) $ unwrap s


-- Connecting -----------------------------------------------------------------
dup_oo    :: Monad m => Sink m a   -> Sink m a -> m (Sink m a)
dup_oo o1 o2 = liftM wrap $ G.dup_oo (unwrap o1) (unwrap o2)

dup_io    :: Monad m => Source m a -> Sink m a -> m (Source m a)
dup_io i1 o2 = liftM wrap $ G.dup_io (unwrap i1) (unwrap o2)

dup_oi    :: Monad m => Sink m a   -> Source m a -> m (Source m a)
dup_oi o1 i2 = liftM wrap $ G.dup_oi (unwrap o1) (unwrap i2)

connect_i :: States  () m (Maybe a)
          => Source m a -> m (Source m a, Source m a)
connect_i i1 = liftM wrap2 $ G.connect_i (unwrap i1)


{-

-- Prepend ----------------------------------------------------------------------
-- | Prepent some more elements into the front of an argument source,
--   producing a result source.
--
--   The results source returns the new elements, then the ones from
--   the argument source.
pre_i :: [a] -> Source IO a -> IO (Source IO a)
pre_i xs (Source pullX)
 = do   
        let !len  = P.length xs
        ref       <- newIORef 0

        let pull_stuff eat eject
             = do ix <- readIORef ref
                  if ix < len

                   then do writeIORef ref (ix + 1)
                           eat (xs !! ix)

                   else do writeIORef ref (ix + 1)
                           pullX eat eject

        return (Source pull_stuff)

{-# INLINE [2] pre_i #-}



-- Groups ---------------------------------------------------------------------
-- | From a stream of values which has consecutive runs of idential values,
--   produce a stream of the lengths of these runs.
-- 
--   Example: groups [4, 4, 4, 3, 3, 1, 1, 1, 4] = [3, 2, 3, 1]
--
groups_i 
        :: (Show a, Eq a) 
        => Source IO a -> IO (Source IO Int)

groups_i (Source pullV)
 = return $ Source pull_n
 where  
        -- Pull a whole run from the source, so that we can produce.
        -- the output element. 
        pull_n eat eject
         = loop_groups Nothing 1#
         where 
                loop_groups !mx !count
                 = pullV eat_v eject_v
                 where  eat_v v
                         = case mx of
                            -- This is the first element that we've read from
                            -- the source.
                            Nothing -> loop_groups (Just v) count

                            -- See if the next element is the same as the one
                            -- we read previously
                            Just x  -> if x == v
                                        then loop_groups (Just x) (count +# 1#)
                                        else eat (I# count)  -- TODO: ** STORE PULLED VALUE FOR LATER
                        {-# INLINE eat_v #-}

                        eject_v 
                         = case mx of
                            -- We've already written our last count, 
                            -- and there are no more elements in the source.
                            Nothing -> eject

                            -- There are no more elements in the source,
                            -- so emit the final count
                            Just _  -> eat (I# count)
                        {-# INLINE eject_v #-}

        {-# INLINE [1] pull_n #-}

{-# INLINE [2] groups_i #-}


-- Pack -----------------------------------------------------------------------
-- | Given a stream of flags and a stream of values, produce a new stream
--   of values where the corresponding flag was True. The length of the result
--   is the length of the shorter of the two inputs.
pack_ii :: Source s Bool -> Source s a -> IO (Source s a)
pack_ii (Source pullF) (Source pullX)
 = return $ Source pull_pack
 where   
        pull_pack eat eject
         = pullF eat_f eject_f
         where eat_f f        = pack_x f
               eject_f        = eject

               pack_x f
                = pullX eat_x eject_x
                where eat_x x = if f then eat x
                                     else pull_pack eat eject

                      eject_x = eject
               {-# INLINE [1] pack_x #-}

        {-# INLINE [1] pull_pack #-}

{-# INLINE [2] pack_ii #-}


-- Folds ----------------------------------------------------------------------
-- | Segmented fold. 
folds_ii 
        :: Monad m
        => (a -> a -> a) 
        -> a
        -> Source m Int 
        -> Source m a 
        -> m (Source m a)

folds_ii f z (Source pullLen) (Source pullX)
 = return $ Source pull_folds
 where  
        pull_folds eat eject
         = pullLen eat_len eject_len
         where 
               eat_len (I# len) = loop_folds len z
               eject_len        = eject
                   
               loop_folds !n !acc
                | tagToEnum# (n ==# 0#) = eat acc
                | otherwise
                = pullX eat_x eject_x
                where 
                      eat_x x = loop_folds (n -# 1#) (f acc x)
                      eject_x = eject

        {-# INLINE [1] pull_folds #-}
{-# INLINE [2] folds_ii #-}


-- Watch ----------------------------------------------------------------------
-- | Pass elements to the provided action as they are pulled from the source.
watch_i :: Monad m => Source m a -> (a -> m ()) -> m (Source m a)
watch_i (Source pullX) f
 = return $ Source pull_watch
 where  
        pull_watch eat eject
         = pullX eat_watch eject_watch
         where
                eat_watch x     = f x >> eat x
                eject_watch     = eject
        {-# INLINE [1] pull_watch #-}
{-# INLINE [2] watch_i #-}


-- | Pass elements to the provided action as they are pushed into the sink.
watch_o :: Monad m => Sink m a ->  (a -> m ())  -> m (Sink m a)
watch_o (Sink push eject) f
 = return $ Sink push_watch eject_watch
 where
        push_watch x    = f x >> push x
        eject_watch     = eject
{-# INLINE [2] watch_o #-}


-- | Like `watch` but doesn't pass elements to another sink.
trigger_o :: Monad m => (a -> m ()) -> m (Sink m a)
trigger_o f
 = discard_o >>= flip watch_o f
{-# INLINE [2] trigger_o #-}


-- Discard --------------------------------------------------------------------
-- | A sink that drops all data on the floor.
--
--   This sink is strict in the elements, so they are demanded before being
--   discarded. Haskell debugging thunks attached to the elements will be demanded.
discard_o :: Monad m => m (Sink m a)
discard_o
 = return $ Sink push_discard eject_discard
 where  
        -- IMPORTANT: push_discard should be strict in the element so that
        -- and Haskell tracing thunks attached to it are evaluated.
        -- We *discard* the elements, but don't completely ignore them.
        push_discard !_ = return ()
        eject_discard   = return ()
{-# INLINE [2] discard_o #-}


-- Ignore ---------------------------------------------------------------------
-- | A sink that ignores all incoming elements.
--
--   This sink is non-strict in the elements. 
--   Haskell tracing thinks attached to the elements will *not* be demanded.
ignore_o :: Monad m => m (Sink m a)
ignore_o
 = return $ Sink push_ignore eject_ignore
 where
        push_ignore _   = return ()
        eject_ignore    = return ()
{-# INLINE [2] ignore_o #-}
-}
