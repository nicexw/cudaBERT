#include "softmax.cuh"

#include "shfl.cuh"
#include "../utils/common.h"
#include "../utils/manager.cuh"

template<typename T> __device__ __forceinline__
void cuWelfordMax(
  const T* tensor,
  const int n1,
  const int n2,
  const int i1,
  T& max_) 
{
  max_= T(-99999);
  if (i1 < n1) {
    // one warp normalizes one n1 index,
    // synchronization is implicit
    // initialize with standard Welford algorithm
    const int numx = blockDim.x * blockDim.y;
    const int thrx = threadIdx.x + threadIdx.y * blockDim.x;
    const T* lvals = tensor + i1*n2;
    int l = 4*thrx;
    for (;  l+3 < n2;  l+=4*numx) {
      for (int k = 0;  k < 4;  ++k) {
        T curr = static_cast<T>(lvals[l+k]);
        max_ = max(max_, curr);
      }
    }
    for (;  l < n2;  ++l) {
      T curr = static_cast<T>(lvals[l]);
      max_ = max(max_, curr);
    }
    // intra-warp reductions
    for (int l = 0;  l <= 4;  ++l) {
      int srcLaneB = (threadIdx.x+(1<<l))&31;
      T maxB = WARP_SHFL(max_, srcLaneB);
      max_ = max(maxB, max_);
    }
    // threadIdx.x == 0 has correct values for each warp
    // inter-warp reductions{
    max_ = WARP_SHFL(max_, 0);
  }
}

template<typename T> __device__ __forceinline__
void cuWelfordSum(
  const T* vals,
  const int n1,
  const int n2,
  const int i1,
  T& sum) 
{
  sum = T(0);
  if (i1 < n1) {
    // one warp normalizes one n1 index,
    // synchronization is implicit
    // initialize with standard Welford algorithm
    const int numx = blockDim.x * blockDim.y;
    const int thrx = threadIdx.x + threadIdx.y * blockDim.x;
    const T* lvals = vals + i1*n2;
    int l = 4*thrx;
    for (;  l+3 < n2;  l+=4*numx) {
      for (int k = 0;  k < 4;  ++k) {
        T curr = static_cast<T>(lvals[l+k]);
        sum += curr;
      }
    }
    for (;  l < n2;  ++l) {
      T curr = static_cast<T>(lvals[l]);
      sum += curr;
    }
    // intra-warp reductions
    for (int l = 0;  l <= 4;  ++l) {
      int srcLaneB = (threadIdx.x+(1<<l))&31;
      T sumB = WARP_SHFL(sum, srcLaneB);
      sum += sumB;
    }
    // threadIdx.x == 0 has correct values for each warp
    // inter-warp reductions{
    sum = WARP_SHFL(sum, 0);
  }
}


template<typename T> __global__
void cuApplySoftmax(
  T* tensor,
  const size_t n1,
  const size_t n2,
  int* mask, 
  size_t batchsize
  ) 
{
  // Merge Mask add to Softmax
  if(mask != nullptr){
    for(size_t i1 = blockIdx.y; i1 < n1; i1 += gridDim.y){
      for(size_t k = threadIdx.x; k < n2; k += blockDim.x){
        size_t index = n2 * ( i1 / ( n1 / batchsize )) + k;
        tensor[i1 * n2 + k] = tensor[i1 * n2 + k] + (1 - mask[index]) * -10000.0;
      }
    }
    __syncthreads();
  }

  // Assumptions:
  // 1) blockDim.x == warpSize
  // 2) Tensors are contiguous
  //
  for(int i1 = blockIdx.y; i1 < n1; i1 += gridDim.y){
    T max_, sum;
    cuWelfordMax(tensor,n1,n2,i1,max_);
    T* vals = tensor + i1*n2;
    const int numx = blockDim.x * blockDim.y;
    const int thrx = threadIdx.x + threadIdx.y * blockDim.x;
    for (int i = thrx;  i < n2;  i+=numx) {
        vals[i] = exp(vals[i] - max_);
    }
    cuWelfordSum(tensor,n1,n2,i1,sum);
    for (int i = thrx;  i < n2;  i+=numx) {
        vals[i] = vals[i] / sum;
    }
    __syncthreads();
  }
}

template<typename T> 
void op_SoftMax::forward(global_handle* handle,
                        T* tensor,
                        size_t n1,
                        size_t n2,
                        int* mask
                        )
{
    const dim3 threads(32,1,1);
    const dim3 blocks(1,min((long)65535,n1),1);
    cuApplySoftmax<<<blocks, threads, 0, handle->cal_stream>>>(
		    tensor,
		    n1,n2,
        mask,
        handle->batchsize
            );
}

template 
void op_SoftMax::forward<float>(
    global_handle* handle,
    float* tensor,
    size_t n1,
    size_t n2,
    int* mask
    );
