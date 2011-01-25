
-- | Basic definitions for stencil handling.
module Data.Array.Repa.Stencil.Base
	( Boundary	(..)
	, Stencil	(..)

	, makeStencil, makeStencil2)
where
import Data.Array.Repa.Base
import Data.Array.Repa.Index


-- | Indicates how to handle the case when the stencil being applied
--   to the input array lies partly outside that array.
data Boundary a
	-- | Treat points outside as having a constant value.
	= BoundConst a	

	-- | Treat points outside as having the same value as the edge pixel.
	| BoundClamp
	deriving (Show)

-- | Represents a convolution stencil that we can apply to array.
data Stencil sh a b

	-- | Static stencils are used when the coefficients are fixed,
	--   and known at compile time.
	= StencilStatic
	{ stencilExtent	:: !sh
	, stencilZero	:: !b 
	, stencilAcc	:: !(sh -> a -> b -> b) }


-- | Make a stencil from a function yielding coefficients at each index.
makeStencil
	:: (Elt a, Num a) 
	=> sh			-- ^ Extent of stencil.
	-> (sh -> Maybe a) 	-- ^ Get the coefficient at this index.
	-> Stencil sh a a

{-# INLINE makeStencil #-}
makeStencil ex getCoeff
 = StencilStatic ex 0 
 $ \ix val acc
	-> case getCoeff ix of
		Nothing		-> acc
		Just coeff	-> acc + val * coeff


-- | Wrapper for `makeStencil` that requires a DIM2 stencil.
makeStencil2
	:: (Elt a, Num a)
	=> Int -> Int		-- ^ extent of stencil
	-> (DIM2 -> Maybe a)	-- ^ Get the coefficient at this index.
	-> Stencil DIM2 a a

{-# INLINE makeStencil2 #-}
makeStencil2 height width getCoeff
	= makeStencil (Z :. height :. width) getCoeff
