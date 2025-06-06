/* Includes, system */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <iostream>
#include <iomanip>
#include <random>
#include <cblas.h>
#include <omp.h>

#include <cuda.h>
#include <cublas_v2.h>
#include <cuda_fp16.h>

#define LIM_CHECK_N 4096
#define LIM_PRINT_N 256
// fraction error   1.0 is 100% 
#define TOLERR 0.0001
#ifdef CPUFP64
    typedef double CPUTYPE;
#else
    typedef float CPUTYPE;
#endif
#include "tools.h"

using namespace std;

int main(int argc, char **argv) {
  cublasStatus_t status;
  if(argc != 9){
      fprintf(stderr, "run as ./prog dev nt n comptype mode\n\n"
              "dev:      Device ID\n"
              "nt:       Number of CPU threads (accelerates data init and CPU mode)\n"
              "m:        Matrix size of M \n"
              "n:        Matrix size of N \n"
              "k:        Matrix size of K \n"
              "comptype: GPU CUBLAS mode\n"
              "mode:     CPU=0,  GPU=1\n"
              "loop:     GPU CUBLAS loop kernel\n\n");
      printArgsInfo();
      return EXIT_FAILURE;
  }
  float gputime_ms;
  int dev = atoi(argv[1]);
  int nt = atoi(argv[2]);
  int M = atoi(argv[3]);
  int N = atoi(argv[4]);
  int K = atoi(argv[5]);
  int comptype = atoi(argv[6]);
  int mode = atoi(argv[7]);
  int loop = atoi(argv[8]);
  printf("\n*********************************************\n"
         "******** CUBLAS Example by Temporal *********\n"
         "*********************************************\n\n");
  printf("dev=%i, nt=%i, m=%i, n=%i, k=%i, cublasType=%i, <mode = %i -> %s>\n\n", dev, nt, M,N,K, comptype, mode, mode == 0? "CPU" : "GPU");
  // host pointers
  ATYPE *h_A;
  BTYPE *h_B;
  CTYPE *h_C;
  CPUTYPE *cblasC;
  // device pointers
  ATYPE *d_A = 0;
  BTYPE *d_B = 0;
  CTYPE *d_C = 0;
  // constants,compute types
  CPTYPE alpha = 1.0f;
  CPTYPE beta  = 0.0f;
  
  // number of elements
  unsigned long nelemA = (unsigned long)M * (unsigned long)K;
  unsigned long nelemB = (unsigned long)K * (unsigned long)N;
  unsigned long nelemC = (unsigned long)M * (unsigned long)N;
  double GBytesUsed = ((double)nelemA*sizeof(ATYPE) + (double)nelemB*sizeof(BTYPE) + (double)nelemC*sizeof(CTYPE))/1e9;
  double t1, t2;
  double TFLOP = 2.0*(double)M*(double)N*(double)K * 1E-12;
  int bitsA = sizeof(ATYPE)*8;
  int bitsB = sizeof(BTYPE)*8;
  int bitsC = sizeof(CTYPE)*8;
  int bitsCPU = sizeof(CPUTYPE)*8;

  cudaDataType dtypeA = dataTypes[hmap(bitsA)];
  cudaDataType dtypeB = dataTypes[hmap(bitsB)];
  cudaDataType dtypeC = dataTypes[hmap(bitsC)];
  const char* dtypeAStr = dataTypesStr[hmap(bitsA)];
  const char* dtypeBStr = dataTypesStr[hmap(bitsB)];
  const char* dtypeCStr = dataTypesStr[hmap(bitsC)];
  const char* dtypeCPU = cblasDataTypesStr[cpuhmap(bitsCPU)];

  gpuErrchk(cudaSetDevice(dev));
  print_gpu_specs(dev);
  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cublasHandle_t handle;
  omp_set_num_threads(nt);
  printf("Matrix size MNK %i %i %i --> %lu nelemA %lu nelemB %lu nelemC\n"
          "GPU: A FP%i (%10s), B FP%i (%10s), C FP%i (%10s)\n"
          "CPU: A FP%i (%10s), B FP%i (%10s), C FP%i (%10s)\n\n", 
          M, N, K, nelemA, nelemB, nelemC,
          bitsA, dtypeAStr,
          bitsB, dtypeBStr,
          bitsC, dtypeCStr, 
          bitsCPU, dtypeCPU,
          bitsCPU, dtypeCPU,
          bitsCPU, dtypeCPU);

  printf("GPU Mem used...................%f GB\n", GBytesUsed); fflush(stdout);
  printf("Pinned Mem.....................");
  #ifdef PINNED
    printf("True\n");
  #else
    printf("False\n");
  #endif



  /* 1) Initialize CUBLAS */
  status = cublasCreate(&handle);
  if (status != CUBLAS_STATUS_SUCCESS){
    fprintf(stderr, "!!!! CUBLAS initialization error\n");
    return EXIT_FAILURE;
  }


  /* 2) Set math mode */
  printf("Compute Type...................%s\n\n", cublasComputeTypesStr[comptype]);
  //status = cublasSetMathMode(handle, cublasMathModes[0]);
  if (status != CUBLAS_STATUS_SUCCESS){
    fprintf(stderr, "!!!! CUBLAS MATH MODE ERROR\n");
    return EXIT_FAILURE;
  }


  /* 3) Allocate and fill host memory for the matrices */
  printf("Host mallocs A B C............."); fflush(stdout);
  t1 = omp_get_wtime();
  #ifdef PINNED
      cudaMallocHost((void**)&h_A, nelemA*sizeof(h_A[0]));
      cudaMallocHost((void**)&h_B, nelemB*sizeof(h_B[0]));
      cudaMallocHost((void**)&h_C, nelemC*sizeof(h_C[0]));
  #else
      h_A = (ATYPE*)(malloc(nelemA * sizeof(h_A[0])));
      h_B = (BTYPE*)(malloc(nelemB * sizeof(h_B[0])));
      h_C = (CTYPE*)(malloc(nelemC * sizeof(h_C[0])));
  #endif

  t2 = omp_get_wtime();
  printf("done: %f secs\n", t2-t1); fflush(stdout);
  printf("Filling matrices in Host......."); fflush(stdout);
  t1 = omp_get_wtime();
  fillMatrixRand<ATYPE>(h_A, nelemA);
  fillMatrixRand<BTYPE>(h_B, nelemB);
  fillMatrixRand<CTYPE>(h_C, nelemC);
  t2 = omp_get_wtime();
  printf("done: %f secs\n", t2-t1); fflush(stdout);
  print_matrix<ATYPE>(h_A, M, K, "MAT A");
  print_matrix<BTYPE>(h_B, K, N, "MAT B");


  /* 4) Allocate device memory for the matrices */
  printf("Device mallocs A B C..........."); fflush(stdout);
  t1 = omp_get_wtime();
  if (cudaMalloc(reinterpret_cast<void **>(&d_A), nelemA * sizeof(d_A[0])) != cudaSuccess) {
        fprintf(stderr, "!!!! device memory allocation error (allocate A)\n");
        return EXIT_FAILURE;
  }

  if (cudaMalloc(reinterpret_cast<void **>(&d_B), nelemB * sizeof(d_B[0])) != cudaSuccess) {
    fprintf(stderr, "!!!! device memory allocation error (allocate B)\n");
    return EXIT_FAILURE;
  }

  if (cudaMalloc(reinterpret_cast<void **>(&d_C), nelemC * sizeof(d_C[0])) != cudaSuccess) {
    fprintf(stderr, "!!!! device memory allocation error (allocate C)\n");
    return EXIT_FAILURE;
  }
  t2 = omp_get_wtime();
  printf("done: %f secs\n", t2-t1); fflush(stdout);



  /* 5) Initialize the device matrices with the host matrices */
  printf("Host -> Device memcpy A........"); fflush(stdout);
  t1 = omp_get_wtime();
  status = cublasSetVector(nelemA, sizeof(h_A[0]), h_A, 1, d_A, 1);
  if (status != CUBLAS_STATUS_SUCCESS) {
    fprintf(stderr, "!!!! device access error (write A)\n");
    return EXIT_FAILURE;
  }
  gpuErrchk(cudaDeviceSynchronize());
  t2 = omp_get_wtime();
  printf("done: %f secs (%f GB/sec)\n", t2-t1, nelemA*sizeof(h_A[0])/(1e9 * (t2-t1))); fflush(stdout);

  printf("Host -> Device memcpy B........"); fflush(stdout);
  t1 = omp_get_wtime();
  status = cublasSetVector(nelemB, sizeof(h_B[0]), h_B, 1, d_B, 1);
  if (status != CUBLAS_STATUS_SUCCESS) {
    fprintf(stderr, "!!!! device access error (write B)\n");
    return EXIT_FAILURE;
  }
  gpuErrchk(cudaDeviceSynchronize());
  t2 = omp_get_wtime();
  printf("done: %f secs (%f GB/sec)\n", t2-t1, nelemB*sizeof(h_B[0])/(1e9 * (t2-t1))); fflush(stdout);

  printf("Host -> Device memcpy C........"); fflush(stdout);
  t1 = omp_get_wtime();
  status = cublasSetVector(nelemC, sizeof(h_C[0]), h_C, 1, d_C, 1);
  if (status != CUBLAS_STATUS_SUCCESS) {
    fprintf(stderr, "!!!! device access error (write C)\n");
    return EXIT_FAILURE;
  }
  gpuErrchk(cudaDeviceSynchronize());
  t2 = omp_get_wtime();
  printf("done: %f secs (%f GB/sec)\n\n", t2-t1, nelemC*sizeof(h_C[0])/(1e9 * (t2-t1))); fflush(stdout);







  /* 6) GEMM -> GPU CUBLAS */
  if(mode==1){
      printf("[CUBLAS] GPU GEMM.............."); fflush(stdout);

      //Warning: 
      // for(uint i=0; i<5; i++)
      // {
      //   status = cublasGemmEx(handle, CUBLAS_OP_N, CUBLAS_OP_N, N, M, K, &alpha,
      //                                     d_B, dtypeA, N,
      //                                     d_A, dtypeB, K,
      //                           &beta,    d_C, dtypeC, N, cublasComputeTypes[comptype],  CUBLAS_GEMM_DEFAULT_TENSOR_OP);
      //   }
      //   if(status != CUBLAS_STATUS_SUCCESS){
      //   fprintf(stderr, "!!!! kernel execution error.\n");
      //   return EXIT_FAILURE;
      // }
      int incx =1;
      int incy =1;
      gpuErrchk(cudaEventRecord(start));
      for(uint i=0; i<loop; i++)
      {

        // status = cublasGemmEx(handle, CUBLAS_OP_N, CUBLAS_OP_N, M, N, K, &alpha,
        //                                   d_A, dtypeA, M,
        //                                   d_B, dtypeB, K,
        //                         &beta,    d_C, dtypeC, M, cublasComputeTypes[comptype],  CUBLAS_GEMM_DEFAULT_TENSOR_OP);
        status = cublasGemmEx(handle, CUBLAS_OP_N, CUBLAS_OP_N, N, M, K, &alpha,
                                          d_B, dtypeA, N,
                                          d_A, dtypeB, K,
                                &beta,    d_C, dtypeC, N,cublasComputeTypes[comptype],  CUBLAS_GEMM_DEFAULT_TENSOR_OP);
        // status = cublasSgemv(handle, CUBLAS_OP_N,  M, K, &alpha,
        //                              d_A, M,
        //                              d_B, incx,
        //                              &beta,    
        //                              d_C,  incy);

        }
        if(status != CUBLAS_STATUS_SUCCESS){
        fprintf(stderr, "!!!! kernel execution error.\n");
        return EXIT_FAILURE;
      }
      gpuErrchk(cudaDeviceSynchronize());
      gpuErrchk(cudaEventRecord(stop));
      gpuErrchk(cudaEventSynchronize(stop));
      gpuErrchk(cudaEventElapsedTime(&gputime_ms, start, stop));
      double gpuTFLOPS = TFLOP/((gputime_ms/loop)/1000.0);
      double gpuGBPS   = ( ((nelemA+nelemB)*sizeof(h_A[0]))/1000000000.0f )/((gputime_ms/loop)/1000.0);
      printf("done: %f ms [%f TFLOPS] [%f GB/s]\n", 1.0f*gputime_ms/loop, gpuTFLOPS,gpuGBPS); fflush(stdout);
  }





  /* 7) GEMM -> CPU BASIC */
  if(mode == 0){
      cblasC = cblas_compute<CPUTYPE>(M,N,K, nelemA,nelemB,nelemC, alpha, beta, h_A, h_B, dtypeCPU, true); 
      /*
      //printf("[CBLAS] Host mallocs A B C............."); fflush(stdout);
      t1 = omp_get_wtime();
      cblasA = (CPUTYPE*)(malloc(nelem * sizeof(CPUTYPE)));
      cblasB = (CPUTYPE*)(malloc(nelem * sizeof(CPUTYPE)));
      cblasC = (CPUTYPE*)(malloc(nelem * sizeof(CPUTYPE)));
      t2 = omp_get_wtime();
      //printf("done: %f secs\n", t2-t1); fflush(stdout);
      //printf("[CBLAS] Filling matrices in Host......."); fflush(stdout);
      t1 = omp_get_wtime();
      copyMatrix<CPUTYPE, ATYPE>(cblasA, h_A, N);
      copyMatrix<CPUTYPE, BTYPE>(cblasB, h_B, N);
      t2 = omp_get_wtime();
      //printf("done: %f secs\n", t2-t1); fflush(stdout);
      t1 = omp_get_wtime();
      printf("[CBLAS] CPU GEMM (%6s)......", dtypeCPU); fflush(stdout);
      #ifdef CPUFP64
          cblas_dgemm(CblasColMajor,CblasNoTrans,CblasNoTrans,N,N,N,alpha,cblasA,N,cblasB,N,beta,cblasC,N);
      #else
          cblas_sgemm(CblasColMajor,CblasNoTrans,CblasNoTrans,N,N,N,alpha,cblasA,N,cblasB,N,beta,cblasC,N);
      #endif

      t2 = omp_get_wtime();
      double cpuTFLOPS = TFLOP/(t2-t1);
      printf("done: %f secs [%f TFLOPS]\n\n", t2-t1, cpuTFLOPS); fflush(stdout);
      print_matrix<CPUTYPE>(cblasC, N, N, "RESULT MAT C (CPU)");
      */
  }





  /* 8) Read the result back */
  if(mode == 1){
      printf("Device -> Host memcpy C........"); fflush(stdout);
      t1 = omp_get_wtime();
      status = cublasGetVector(nelemC, sizeof(h_C[0]), d_C, 1, h_C, 1);
      if (status != CUBLAS_STATUS_SUCCESS) {
        fprintf(stderr, "!!!! device access error (read C)\n");
        return EXIT_FAILURE;
      }
      t2 = omp_get_wtime();
      printf("done: %f secs (%f GB/sec)\n", t2-t1, nelemC*sizeof(h_C[0])/(1e9*(t2-t1))); fflush(stdout);
      print_matrix<CTYPE>(h_C, N, M, "RESULT MAT C (GPU)");
  }




  /* 9) Check result against reference */
  if(mode == 1 && N <= LIM_CHECK_N){
      printf("Verify result.................."); fflush(stdout);
      t1 = omp_get_wtime();
      cblasC = cblas_compute<CPUTYPE>(M,N,K, nelemA,nelemB,nelemC, alpha, beta, h_A, h_B, dtypeCPU, false); 
      double maxError = computeMaxError<CPUTYPE>(cblasC, h_C, N); 
      t2 = omp_get_wtime();
      printf("done: %f secs (maxError = %f%%, TOL = %f%%)\n%s\n\n", t2-t1,
              maxError*100.0, TOLERR*100.0, 
              maxError <= TOLERR ? (const char*)"pass" : (const char*) "failed"); fflush(stdout);
      free(cblasC);
  }






  /* 10) Memory clean up */
  #ifdef PINNED
      cudaFreeHost(h_A);
      cudaFreeHost(h_B);
      cudaFreeHost(h_C);
  #else
      free(h_A);
      free(h_B);
      free(h_C);
  #endif

  if (cudaFree(d_A) != cudaSuccess) {
    fprintf(stderr, "!!!! memory free error (A)\n");
    return EXIT_FAILURE;
  }
  if (cudaFree(d_B) != cudaSuccess) {
    fprintf(stderr, "!!!! memory free error (B)\n");
    return EXIT_FAILURE;
  }
  if (cudaFree(d_C) != cudaSuccess) {
    fprintf(stderr, "!!!! memory free error (C)\n");
    return EXIT_FAILURE;
  }

  /* 11) Shutdown */
  status = cublasDestroy(handle);
  if (status != CUBLAS_STATUS_SUCCESS) {
    fprintf(stderr, "!!!! shutdown error (A)\n");
    return EXIT_FAILURE;
  }
}
