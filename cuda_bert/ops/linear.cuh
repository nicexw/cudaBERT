#ifndef LINEAR_CUDA_BERT
#define LINEAR_CUDA_BERT

#include "op_kernel.cuh"
#include "../utils/common.h"

__global__ void MemoryCpyLinear(float* out, float* in, size_t max, size_t warpsize, float mul = 1.0) ;

class op_Linear : public op_kernel{
  public:
    op_Linear(std::string key_kernel, 
              std::string key_bias,
              global_handle* handle)
                 : op_kernel(handle) {
        std::vector<std::string> keys = {key_kernel};
        tagged_tensor* tt = look_up_tts(handle->tts, keys);
        kernel = tt->gpu_mem;
        keys = {key_bias};
        tt = look_up_tts(handle->tts, keys);
        bias = tt->gpu_mem;
    }

    ~op_Linear(){
      checkCudaErrors(cudaFree(kernel));
      checkCudaErrors(cudaFree(bias));
    }

    template <typename T>
    void forward(
                T* &output, 
                T* input, 
                size_t n, 
                size_t k, 
                size_t m,
                bool is_prepare=false,
                bool debug=false);

    template<typename T>
    void backward(T *dout, size_t n,
                  size_t k,
                  size_t m);

    void update();

private:
    size_t n, k; // Shape of Weight: [n, k]

    float *kernel;
    float *bias;
    float *grad_kernel;
    float *grad_bias;
public:
    float *grad_input;
};

class op_BatchedLinear : public op_kernel{
  public:
    op_BatchedLinear( std::string key_query_kernel, 
                      std::string key_query_bias,
                      std::string key_key_kernel, 
                      std::string key_key_bias,
                      std::string key_val_kernel, 
                      std::string key_val_bias,
                      global_handle* handle);

    ~op_BatchedLinear(){
      checkCudaErrors(cudaFree(query_kernel));
      checkCudaErrors(cudaFree(query_bias));
      checkCudaErrors(cudaFree(key_bias));
      checkCudaErrors(cudaFree(val_bias));
    }

    template <typename T>
    void forward(
                T* &output, 
                T* input, 
                size_t n, 
                size_t k, 
                size_t m,
                bool is_prepare=false,
                bool debug=false);

    void backward();

    void update();

  private:
    size_t n, k; // Shape of Weight: [n, k]

    float* query_kernel;
    float* query_bias;
    float* key_kernel; 
    float* key_bias;
    float* val_kernel; 
    float* val_bias;

    float* batch_attentin_weights;
};

#endif
