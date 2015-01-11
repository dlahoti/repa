
module Data.Repa.Array.Delayed
        ( D(..), Array(..)
        , fromFunction, toFunction
        , delay
        , map
        , zipWith
        , (+^), (-^), (*^), (/^))
where
import Data.Repa.Array.Internals.Bulk
import Data.Repa.Array.Internals.Load
import Data.Repa.Array.Internals.Target
import Data.Repa.Array.Internals.Shape
import Data.Repa.Array.Internals.Index
import Data.Array.Repa.Eval.Elt
import Debug.Trace
import GHC.Exts
import qualified Data.Array.Repa.Eval.Par       as Par
import qualified Data.Array.Repa.Eval.Seq       as Seq
import Prelude hiding (map, zipWith)


-------------------------------------------------------------------------------
-- | Delayed arrays are represented as functions from the index to element
--   value.
--
--   Every time you index into a delayed array the element at that position 
--   is recomputed.
data D = D

-- | Delayed arrays.
instance Shape sh => Bulk D sh a where
 data Array D sh a
        = ADelayed  
                !sh 
                (sh -> a) 

 index       (ADelayed _  f) ix  = f ix
 {-# INLINE index #-}

 extent (ADelayed sh _)          = sh
 {-# INLINE extent #-}


-- Load -----------------------------------------------------------------------
instance Shape sh => Load D sh e where
 loadS (ADelayed sh get) !buf
  = do  let !(I# len)   = size sh
        let write ix x  = unsafeWriteBuffer buf (I# ix) x
        let get' ix     = get $ fromIndex sh (I# ix)
        Seq.fillLinear  write get' len
        touchBuffer  buf
 {-# INLINE [1] loadS #-}

 loadP gang (ADelayed sh get) !buf
  = do  traceEventIO "Repa.loadP[Delayed]: start"
        let !(I# len)   = size sh
        let write ix x  = unsafeWriteBuffer buf (I# ix) x
        let get' ix     = get $ fromIndex sh (I# ix)
        Par.fillChunked gang write get' len 
        touchBuffer  buf
        traceEventIO "Repa.loadP[Delayed]: end"
 {-# INLINE [1] loadP #-}


instance Elt e => LoadRange D DIM2 e where
 loadRangeS  (ADelayed (Z :. _h :. (I# w)) get) !buf
             (Z :. (I# y0) :. (I# x0)) (Z :. (I# h0) :. (I# w0))
  = do  let write ix x  = unsafeWriteBuffer buf (I# ix) x
        let get' x y    = get (Z :. I# y :. I# x)
        Seq.fillBlock2 write get' w x0 y0 w0 h0
        touchBuffer buf
 {-# INLINE [1] loadRangeS #-}

 loadRangeP  gang
             (ADelayed (Z :. _h :. (I# w)) get) !buf
             (Z :. (I# y0) :. (I# x0)) (Z :. (I# h0) :. (I# w0))
  = do  traceEventIO "Repa.loadRangeP[Delayed]: start"
        let write ix x  = unsafeWriteBuffer buf (I# ix) x
        let get' x y    = get (Z :. I# y :. I# x)
        Par.fillBlock2  gang write get' w x0 y0 w0 h0
        touchBuffer  buf
        traceEventIO "Repa.loadRangeP[Delayed]: end"
 {-# INLINE [1] loadRangeP #-}


-- Conversions ----------------------------------------------------------------
-- | O(1). Wrap a function as a delayed array.
fromFunction :: sh -> (sh -> a) -> Array D sh a
fromFunction sh f 
        = ADelayed sh f 
{-# INLINE [1] fromFunction #-}


-- | O(1). Produce the extent of an array, and a function to retrieve an
--   arbitrary element.
toFunction 
        :: Bulk r sh a
        => Array r sh a -> (sh, sh -> a)
toFunction arr
 = case delay arr of
        ADelayed sh f -> (sh, f)
{-# INLINE [1] toFunction #-}


-- | O(1). Delay an array.
--   This wraps the internal representation to be a function from
--   indices to elements, so consumers don't need to worry about
--   what the previous representation was.
--
delay   :: Bulk  r sh e
        => Array r sh e -> Array D sh e
delay arr = ADelayed (extent arr) (index arr)
{-# INLINE [1] delay #-}


-- Operators ------------------------------------------------------------------
-- | Apply a worker function to each element of an array, 
--   yielding a new array with the same extent.
map     :: (Shape sh, Bulk r sh a)
        => (a -> b) -> Array r sh a -> Array D sh b
map f arr
 = case delay arr of
        ADelayed sh g -> ADelayed sh (f . g)
{-# INLINE [1] map #-}


-- ZipWith --------------------------------------------------------------------
-- | Combine two arrays, element-wise, with a binary operator.
--      If the extent of the two array arguments differ,
--      then the resulting array's extent is their intersection.
--
zipWith :: (Shape sh, Bulk r1 sh a, Bulk r2 sh b)
        => (a -> b -> c)
        -> Array r1 sh a -> Array r2 sh b
        -> Array D  sh c

zipWith f arr1 arr2
 = fromFunction (intersectDim (extent arr1) (extent arr2)) 
                get_zipWith
 where  get_zipWith ix  
         = f (arr1 `index` ix) (arr2 `index` ix)
        {-# INLINE get_zipWith #-}

infixl 7  *^, /^
infixl 6  +^, -^

(+^)    = zipWith (+)
{-# INLINE (+^) #-}

(-^)    = zipWith (-)
{-# INLINE (-^) #-}

(*^)    = zipWith (*)
{-# INLINE (*^) #-}

(/^)    = zipWith (/)
{-# INLINE (/^) #-}

