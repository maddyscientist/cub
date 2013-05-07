/******************************************************************************
 * Copyright (c) 2011, Duane Merrill.  All rights reserved.
 * Copyright (c) 2011-2013, NVIDIA CORPORATION.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the NVIDIA CORPORATION nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 ******************************************************************************/

/**
 * \file
 * cub::GridMappingStrategy enumerates alternative strategies for mapping
 * constant-sized tiles of device-wide data onto a grid of CUDA thread
 * blocks.
 */

#pragma once

#include "grid_even_share.cuh"
#include "grid_queue.cuh"
#include "../util_namespace.cuh"

/// Optional outer namespace(s)
CUB_NS_PREFIX

/// CUB namespace
namespace cub {


/**
 * \addtogroup GridModule
 * @{
 */


/******************************************************************************
 * Mapping policies
 *****************************************************************************/


/**
 * \brief GridMappingStrategy enumerates alternative strategies for mapping constant-sized tiles of device-wide data onto a grid of CUDA thread blocks.
 */
enum GridMappingStrategy
{
    /**
     * \brief An "even-share" strategy for assigning input tiles to thread blocks.
     *
     * \par Overview
     * The input is evenly partitioned into \p p segments, where \p p is
     * constant and corresponds loosely to the number of thread blocks that may
     * actively reside on the target device. Each segment is comprised of
     * consecutive tiles, where a tile is a small, constant-sized unit of input
     * to be processed to completion before the thread block terminates or
     * obtains more work.  The kernel invokes \p p thread blocks, each
     * of which iteratively consumes a segment of <em>n</em>/<em>p</em> elements
     * in tile-size increments.
     */
    GRID_MAPPING_EVEN_SHARE,

    /**
     * \brief A dynamic "queue-based" strategy for assigning input tiles to thread blocks.
     *
     * \par Overview
     * The input is treated as a queue to be dynamically consumed by a grid of
     * thread blocks.  Work is atomically dequeued in tiles, where a tile is a
     * unit of input to be processed to completion before the thread block
     * terminates or obtains more work.  The grid size \p p is constant,
     * loosely corresponding to the number of thread blocks that may actively
     * reside on the target device.
     */
    GRID_MAPPING_DYNAMIC,
};



/******************************************************************************
 * Mapping engines
 *****************************************************************************/

/**
 * \brief Uses a GridEvenShare descriptor to dispatch tiles of work to a thread block abstraction of type \p Tiles.  (See GridMappingStrategy::GRID_MAPPING_EVEN_SHARE.)
 *
 * Expects the \p Tiles type to have the following member functions for
 * - Tile processing:
 *   - <tt>void ConsumeTile(bool sync_after, SizeT block_offset, SizeT valid_tile_items);</tt>
 * - Getting the maximum number of items processed per call to <tt>Tiles::ConsumeTile</tt>:
 *   - <tt>int TileItems()</tt>
 * - Finalization:
 *   - <tt>void Finalize(Result &result);</tt>
 *
 * \tparam Tiles    <b>[inferred]</b> Thread block abstraction type for tile processing
 * \tparam SizeT        <b>[inferred]</b> Integral type used for global array indexing
 * \tparam Result       <b>[inferred]</b> Result type to be returned by the Tiles instance
 */

template <
    typename                Tiles,
    typename                SizeT,
    typename                Result>
__device__ __forceinline__ void BlockConsumeTiles(
    Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
    SizeT                   block_offset,       ///< [in] Threadblock begin offset (inclusive)
    SizeT                   block_oob,          ///< [in] Threadblock end offset (exclusive)
    Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
{
    bool sync_after = true;

    // Number of items per tile that can be processed by tiles
    int tile_items = tiles.TileItems();

    // Consume any full tiles
    while (block_offset + tile_items <= block_oob)
    {
        tiles.ConsumeTile(sync_after, block_offset, tile_items);
        if (sync_after) __syncthreads();

        block_offset += tile_items;
    }

    // Consume any remaining input
    if (block_offset < block_oob)
    {
        tiles.ConsumeTile(sync_after, block_offset, block_oob - block_offset);
        if (sync_after) __syncthreads();
    }

    // Compute the block-wide reduction (every thread has a valid input)
    tiles.Finalize(result);
}


/**
 * \brief Uses a GridEvenShare descriptor to dispatch tiles of work to a thread block abstraction of type \p Tiles.  (See GridMappingStrategy::GRID_MAPPING_EVEN_SHARE.)
 *
 * Expects the \p Tiles type to have the following member functions for
 * - Tile processing:
 *   - <tt>void ConsumeTile(bool sync_after, SizeT block_offset, SizeT valid_tile_items);</tt>
 * - Getting the maximum number of items processed per call to <tt>Tiles::ConsumeTile</tt>:
 *   - <tt>int TileItems()</tt>
 * - Finalization:
 *   - <tt>void Finalize(Result &result);</tt>
 *
 * \tparam Tiles    <b>[inferred]</b> Thread block abstraction type for tile processing
 * \tparam SizeT        <b>[inferred]</b> Integral type used for global array indexing
 * \tparam Result       <b>[inferred]</b> Result type to be returned by the Tiles instance
 */

template <
    typename                Tiles,
    typename                SizeT,
    typename                Result>
__device__ __forceinline__ void BlockConsumeTiles(
    Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
    SizeT                   num_items,          ///< [in] Total number of global input items
    GridEvenShare<SizeT>    &even_share,        ///< [in] GridEvenShare descriptor
    Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
{
    even_share.BlockInit();
    BlockConsumeTiles(tiles, even_share.block_offset, even_share.block_oob, result);
}



/**
 * \brief Uses a GridEvenShare descriptor to dispatch tiles of work to a thread block abstraction of type \p Tiles.  The first tile given to each thread block is flagged as such. (See GridMappingStrategy::GRID_MAPPING_EVEN_SHARE.)
 *
 * Expects the \p Tiles type to have the following member functions for
 * - Tile processing:
 *   - <tt>void ConsumeTile(bool sync_after, SizeT block_offset, SizeT valid_tile_items, is_first_tile);</tt>
 * - Getting the maximum number of items processed per call to <tt>Tiles::ConsumeTile</tt>:
 *   - <tt>int TileItems()</tt>
 * - Finalization:
 *   - <tt>void Finalize(Result &result);</tt>
 *
 * \tparam Tiles    <b>[inferred]</b> Thread block abstraction type for tile processing
 * \tparam SizeT        <b>[inferred]</b> Integral type used for global array indexing
 * \tparam Result       <b>[inferred]</b> Result type to be returned by the Tiles instance
 */
template <
    typename                Tiles,
    typename                SizeT,
    typename                Result>
__device__ __forceinline__ void BlockConsumeTilesFlagFirst(
    Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
    SizeT                   block_offset,       ///< [in] Threadblock begin offset (inclusive)
    SizeT                   block_oob,          ///< [in] Threadblock end offset (exclusive)
    Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
{
    bool sync_after = true;

    // Number of items per tile that can be processed by tiles
    int tile_items = tiles.TileItems();

    if (block_offset + tile_items <= block_oob)
    {
        // We have at least one full tile to consume
        tiles.ConsumeTile(sync_after, block_offset, tile_items, true);
        if (sync_after) __syncthreads();

        block_offset += tile_items;

        // Consume any other full tiles
        while (block_offset + tile_items <= block_oob)
        {
            tiles.ConsumeTile(sync_after, block_offset, tile_items, false);
            if (sync_after) __syncthreads();

            block_offset += tile_items;
        }

        // Consume any remaining input
        if (block_offset < block_oob)
        {
            tiles.ConsumeTile(sync_after, block_offset, block_oob - block_offset, false);
            if (sync_after) __syncthreads();
        }
    }
    else
    {
        // We have less than a full tile to consume
        SizeT block_items = block_oob - block_offset;

        tiles.ConsumeTile(sync_after, block_offset, block_items, true);
        if (sync_after) __syncthreads();
    }

    // Compute the block-wide reduction (every thread has a valid input)
    tiles.Finalize(result);
}


/**
 * \brief Uses a GridEvenShare descriptor to dispatch tiles of work to a thread block abstraction of type \p Tiles.  The first tile given to each thread block is flagged as such. (See GridMappingStrategy::GRID_MAPPING_EVEN_SHARE.)
 *
 * Expects the \p Tiles type to have the following member functions for
 * - Tile processing:
 *   - <tt>void ConsumeTile(bool sync_after, SizeT block_offset, SizeT valid_tile_items, is_first_tile);</tt>
 * - Getting the maximum number of items processed per call to <tt>Tiles::ConsumeTile</tt>:
 *   - <tt>int TileItems()</tt>
 * - Finalization:
 *   - <tt>void Finalize(Result &result);</tt>
 *
 * \tparam Tiles    <b>[inferred]</b> Thread block abstraction type for tile processing
 * \tparam SizeT        <b>[inferred]</b> Integral type used for global array indexing
 * \tparam Result       <b>[inferred]</b> Result type to be returned by the Tiles instance
 */
template <
    typename                Tiles,
    typename                SizeT,
    typename                Result>
__device__ __forceinline__ void BlockConsumeTilesFlagFirst(
    Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
    SizeT                   num_items,          ///< [in] Total number of global input items
    GridEvenShare<SizeT>    &even_share,        ///< [in] GridEvenShare descriptor
    Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
{
    even_share.BlockInit();
    BlockConsumeTilesFlagFirst(tiles, even_share.block_offset, even_share.block_oob, result);
}



/**
 * \brief Uses a GridQueue descriptor to dispatch tiles of work to a thread block abstraction of type \p Tiles.  (See GridMappingStrategy::GRID_MAPPING_DYNAMIC.)
 *
 * Expects the \p Tiles type to have the following member functions for
 * - Tile processing:
 *   - <tt>void ConsumeTile(bool sync_after, SizeT block_offset, SizeT valid_tile_items);</tt>
 * - Getting the maximum number of items processed per call to <tt>Tiles::ConsumeTile</tt>:
 *   - <tt>int TileItems()</tt>
 * - Finalization:
 *   - <tt>void Finalize(Result &result);</tt>
 *
 * \tparam Tiles    <b>[inferred]</b> Thread block abstraction type for tile processing
 * \tparam SizeT        <b>[inferred]</b> Integral type used for global array indexing
 * \tparam Result       <b>[inferred]</b> Result type to be returned by the Tiles instance
 */
template <
    typename                Tiles,
    typename                SizeT,
    typename                Result>
__device__ __forceinline__ void BlockConsumeTiles(
    Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
    SizeT                   num_items,          ///< [in] Total number of global input items
    GridQueue<SizeT>        &queue,             ///< [in,out] GridQueue descriptor
    Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
{
    // Shared tile-processing offset obtained dynamically from queue
    __shared__ SizeT dynamic_block_offset;

    bool sync_after = true;

    // Number of items per tile that can be processed by tiles
    int tile_items = tiles.TileItems();

    // There are tiles left to consume
    while (true)
    {
        // Dequeue up to tile_items
        if (threadIdx.x == 0)
        {
            dynamic_block_offset = queue.Drain(tile_items);
        }

        __syncthreads();

        SizeT block_offset = dynamic_block_offset;

        __syncthreads();

        if (block_offset + tile_items > num_items)
        {
            if (block_offset < num_items)
            {
                // We have less than a full tile to consume
                tiles.ConsumeTile(sync_after, block_offset, num_items - block_offset);
                if (sync_after) __syncthreads();
            }

            // No more work to do
            break;
        }

        // We have a full tile to consume
        tiles.ConsumeTile(sync_after, block_offset, tile_items);
    }

    tiles.Finalize(result);
}



/**
 * \brief Uses a GridQueue descriptor to dispatch tiles of work to a thread block abstraction of type \p Tiles.  The first tile given to each thread block is flagged as such. (See GridMappingStrategy::GRID_MAPPING_DYNAMIC.)
 *
 * Expects the \p Tiles type to have the following member functions for
 * - Tile processing:
 *   - <tt>void ConsumeTile(bool sync_after, SizeT block_offset, SizeT valid_tile_items, is_first_tile);</tt>
 * - Getting the maximum number of items processed per call to <tt>Tiles::ConsumeTile</tt>:
 *   - <tt>int TileItems()</tt>
 * - Finalization:
 *   - <tt>void Finalize(Result &result);</tt>
 *
 * \tparam Tiles    <b>[inferred]</b> Thread block abstraction type for tile processing
 * \tparam SizeT        <b>[inferred]</b> Integral type used for global array indexing
 * \tparam Result       <b>[inferred]</b> Result type to be returned by the Tiles instance
 */
template <
    typename                Tiles,
    typename                SizeT,
    typename                Result>
__device__ __forceinline__ void BlockConsumeTilesFlagFirst(
    Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
    SizeT                   num_items,          ///< [in] Total number of global input items
    GridQueue<SizeT>        &queue,             ///< [in,out] GridQueue descriptor
    Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
{
    // Shared tile-processing offset obtained dynamically from queue
    __shared__ SizeT dynamic_block_offset;

    bool sync_after = true;

    // Number of items per tile that can be processed by tiles
    int tile_items = tiles.TileItems();

    // We give each thread block at least one tile of input.
    SizeT block_offset = blockIdx.x * tile_items;

    // Check if we have a full tile to consume
    if (block_offset + tile_items <= num_items)
    {
        tiles.ConsumeTile(sync_after, block_offset, tile_items, true);
        if (sync_after) __syncthreads();

        // Now that every block in the kernel has gotten a tile, attempt to dynamically consume any remaining
        SizeT even_share_base = gridDim.x * tile_items;
        if (even_share_base < num_items)
        {
            // There are tiles left to consume
            while (true)
            {
                // Dequeue up to tile_items
                if (threadIdx.x == 0)
                {
                    dynamic_block_offset = queue.Drain(tile_items) + even_share_base;
                }

                __syncthreads();

                block_offset = dynamic_block_offset;

                __syncthreads();

                if (block_offset + tile_items > num_items)
                {
                    if (block_offset < num_items)
                    {
                        // We have less than a full tile to consume
                        tiles.ConsumeTile(sync_after, block_offset, num_items - block_offset, false);
                        if (sync_after) __syncthreads();
                    }

                    // No more work to do
                    break;
                }

                // We have a full tile to consume
                tiles.ConsumeTile(sync_after, block_offset, tile_items, false);
            }
        }
    }
    else
    {
        // We have less than a full tile to consume
        tiles.ConsumeTile(sync_after, block_offset, num_items - block_offset, true);
        if (sync_after) __syncthreads();
    }

    // Compute the block-wide reduction (every thread has a valid input)
    tiles.Finalize(result);

}



/******************************************************************************
 * Type-directed dispatch to mapping engines
 *****************************************************************************/


#ifndef DOXYGEN_SHOULD_SKIP_THIS    // Do not document

/**
 * \brief Dispatch helper for statically selecting between mapping strategies (e.g., to avoid compiling an alternative that is invaild for a given architecture)
 */
template <GridMappingStrategy MAPPING_STRATEGY>
struct GridMapping;

/**
 * Even-share specialization of GridMapping
 */
template<>
struct GridMapping<GRID_MAPPING_EVEN_SHARE>
{
    template <
        typename                Tiles,
        typename                SizeT,
        typename                Result>
    static __device__ __forceinline__ void BlockConsumeTiles(
        Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
        SizeT                   num_items,          ///< [in] Total number of global input items
        GridEvenShare<SizeT>    &even_share,        ///< [in] GridEvenShare descriptor
        GridQueue<SizeT>        &queue,             ///< [in,out] GridQueue descriptor
        Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
    {
        cub::BlockConsumeTiles(tiles, num_items, even_share, result);
    }

    template <
        typename                Tiles,
        typename                SizeT,
        typename                Result>
    static __device__ __forceinline__ void BlockConsumeTilesFlagFirst(
        Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
        SizeT                   num_items,          ///< [in] Total number of global input items
        GridEvenShare<SizeT>    &even_share,        ///< [in] GridEvenShare descriptor
        GridQueue<SizeT>        &queue,             ///< [in,out] GridQueue descriptor
        Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
    {
        cub::BlockConsumeTilesFlagFirst(tiles, num_items, even_share, result);
    }
};


/**
 * Even-share specialization of GridMapping
 */
template<>
struct GridMapping<GRID_MAPPING_DYNAMIC>
{
    template <
        typename                Tiles,
        typename                SizeT,
        typename                Result>
    static __device__ __forceinline__ void BlockConsumeTiles(
        Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
        SizeT                   num_items,          ///< [in] Total number of global input items
        GridEvenShare<SizeT>    &even_share,        ///< [in] GridEvenShare descriptor
        GridQueue<SizeT>        &queue,             ///< [in,out] GridQueue descriptor
        Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
    {
        cub::BlockConsumeTiles(tiles, num_items, queue, result);
    }

    template <
        typename                Tiles,
        typename                SizeT,
        typename                Result>
    static __device__ __forceinline__ void BlockConsumeTilesFlagFirst(
        Tiles               &tiles,        ///< [in,out] Threadblock abstraction for tile processing
        SizeT                   num_items,          ///< [in] Total number of global input items
        GridEvenShare<SizeT>    &even_share,        ///< [in] GridEvenShare descriptor
        GridQueue<SizeT>        &queue,             ///< [in,out] GridQueue descriptor
        Result                  &result)            ///< [out] Result returned by <tt>tiles::Finalize()</tt>
    {
        cub::BlockConsumeTilesFlagFirst(tiles, num_items, queue, result);
    }
};



#endif // DOXYGEN_SHOULD_SKIP_THIS



/** @} */       // end group GridModule

}               // CUB namespace
CUB_NS_POSTFIX  // Optional outer namespace(s)
