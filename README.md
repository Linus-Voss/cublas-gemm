# CUBLAS GEMM Example
A CUBLAS Matrix Multiply (GEMM) example.

## Requirements:
	- Nvidia GPU supporting CUDA
	- CUDA v11.0 or greater
	- CUBLAS v11.0 (should come with CUDA)
	- openblas (max-perf CPU test)

## Install and Compile:
	a) Clone Repo:
        git clone https://github.com/Linus-Voss/cublas-gemm.git

	b) Compile:
        cd cublas-gemm
        make

    c) Data Types:
        You can specify the data type (half, float) for each matrix
        Example:
        make ATYPE=half BTYPE=half CTYPE=half CPTYPE=half
        

## Run:
    a) Run:
            run as ./prog dev nt n comptype mode
            
            dev:      Device ID
            nt:       Number of CPU threads (accelerates data init and CPU mode)
            m:        Matrix size of M
            n:        Matrix size of N
            k:        Matrix size of K
            comptype: GPU CUBLAS mode (should be same witch CPTYPE)
            mode:     CPU=0,  GPU=1
            loop:     GPU CUBLAS loop kernel

    b) CUBLAS Compute Types:
            0  = CUBLAS_COMPUTE_16F
            1  = CUBLAS_COMPUTE_16F_PEDANTIC
            2  = CUBLAS_COMPUTE_32F
            3  = CUBLAS_COMPUTE_32F_PEDANTIC
            4  = CUBLAS_COMPUTE_32F_FAST_16F
            5  = CUBLAS_COMPUTE_32F_FAST_16BF
            6  = CUBLAS_COMPUTE_32F_FAST_TF32
            7  = CUBLAS_COMPUTE_64F
            8  = CUBLAS_COMPUTE_64F_PEDANTIC
            9  = CUBLAS_COMPUTE_32I
            10 = CUBLAS_COMPUTE_32I_PEDANTIC

## Example executions:
    a) make ATYPE=float BTYPE=float CTYPE=float CPTYPE=float
        ./prog 0 4 8192 8192 8192 2 1 10000

    b) make ATYPE=half BTYPE=half CTYPE=half CPTYPE=half
        ./prog 0 4 8192 8192 8192 0 1 10000
	
    c) make ATYPE=half BTYPE=half CTYPE=half CPTYPE=float
        ./prog 0 4 8192 8192 8192 0 2 10000


    d) [CPU CBLAS] FP32 Using 8 CPU threads 
        make
	./prog 0 8 8192 8192 8192 0 0 

    e) [CPU CBLAS] FP64 Using 8 CPU threads 
        make CPUFP64=CPUFP64
       ./prog 0 8 8192 8192 8192 0 0 
