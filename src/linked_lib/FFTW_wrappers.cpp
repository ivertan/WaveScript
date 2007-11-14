
// Wrappers for functions from fftw.
// Only included when the corresponding wavescript functions are invoked.

   //  DEPRECATED:
   //  We should keep a hash table of common plans.
   //static int fft(SigSeg<double> input) {
   static RawSeg sigseg_fftR2C(RawSeg input) {
      int len = input.length();
      int len_out = (len / 2) + 1;

      Byte* temp;
      RawSeg rs(0, len_out, DataSeg, 0, sizeof(wscomplex_t), Unitless,true);
      rs.getDirect(0, len_out, temp);
      wscomplex_t* out_buf = (wscomplex_t*)temp;
      input.getDirect(0, input.length(), temp);
      wsfloat_t* in_buf = (wsfloat_t*)temp;

      // Real to complex:
      fftwf_plan plan = fftwf_plan_dft_r2c_1d(len, in_buf, (fftwf_complex*)out_buf, FFTW_ESTIMATE);      
      fftwf_execute(plan);
      fftwf_destroy_plan(plan);           
      rs.releaseAll();
      input.release(temp);
      return rs;
   }


Mutex planner_lock;

#define complexarr boost::intrusive_ptr< WSArrayStruct<wscomplex_t> >
#define floatarr   boost::intrusive_ptr< WSArrayStruct<wsfloat_t> >

   static complexarr fftR2C(floatarr& input) {
      int len = input->len;
      int len_out = (len / 2) + 1;     
      wsfloat_t*   in_buf  = (wsfloat_t*)input->data; 
      wscomplex_t* out_buf = new wscomplex_t[len_out];

      //printf(" FFT: %d->%d\n", len, len_out);

      // Inefficient!  This approach makes a new plan every time.
      // Real to complex:
#ifndef BOOST_SP_DISABLE_THREADS
      planner_lock.lock();
      fftwf_plan plan = fftwf_plan_dft_r2c_1d(len, in_buf, (fftwf_complex*)out_buf, FFTW_ESTIMATE);
      planner_lock.unlock();
#else 
      fftwf_plan plan = fftwf_plan_dft_r2c_1d(len, in_buf, (fftwf_complex*)out_buf, FFTW_ESTIMATE);
#endif
      fftwf_execute(plan);
#ifndef BOOST_SP_DISABLE_THREADS
      planner_lock.lock();
      fftwf_destroy_plan(plan);           
      planner_lock.unlock();
#else 
      fftwf_destroy_plan(plan);           
#endif
      //WSArrayStruct<wscomplex_t>* result = (WSArrayStruct<wscomplex_t>*)malloc(sizeof(WSArrayStruct<wscomplex_t>));
      WSArrayStruct<wscomplex_t>* result = new WSArrayStruct<wscomplex_t>;
      result->rc = 0;
      result->len = len_out;
      result->data = out_buf;
      return complexarr(result);
   }




// Need to implement the memoized version to play nicer with thread safety.

/*

int        last_plan_size = 0;
fftwf_plan cached_plan;
float*     cached_inbuf;
_Complex float*   cached_outbuf;

   static complexarr memoized_fftR2C(floatarr& input) {
      int len = input->len;
      int len_out = (len / 2) + 1;     
      wsfloat_t*   in_buf  = (wsfloat_t*)input->data; 
      wscomplex_t* out_buf = new wscomplex_t[len_out];

      // First we worry about setting up the plan:
      if (last_plan_size == 0) {
        fprintf(stderr, "Allocating fftw plan for the first time, size %d\n", len);
	fflush(stderr);
      } else if (last_plan_size != len) {
        fprintf(stderr, "REALLOCATING cached fftw plan, size %d\n", len);
        planner_lock.lock();
      	fftwf_destroy_plan(cached_plan);
	fftwf_free(cached_inbuf);
	fftwf_free(cached_outbuf);
        planner_lock.lounck();
      }
      if (last_plan_size != len) {
	last_plan_size = len;
	cached_inbuf  = fftwf_malloc(len     * sizeof(float));
	cached_outbuf = fftwf_malloc(len_out * sizeof(_Complex float));	
	// FFTW_MEASURE, FFTW_PATIENT, FFTW_EXHAUSTIVE
        cached_plan = fftwf_plan_dft_r2c_1d(len, cached_inbuf, (fftwf_complex*)cached_outbuf, FFTW_ESTIMATE);
	// FFTW_PATIENT
      }
      
      

      fftwf_plan plan = fftwf_plan_dft_r2c_1d(len, in_buf, (fftwf_complex*)out_buf, FFTW_ESTIMATE);
      planner_lock.unlock();

      fftwf_execute(plan);

      planner_lock.lock();
      fftwf_destroy_plan(plan);           
      planner_lock.unlock();

      //WSArrayStruct<wscomplex_t>* result = (WSArrayStruct<wscomplex_t>*)malloc(sizeof(WSArrayStruct<wscomplex_t>));
      WSArrayStruct<wscomplex_t>* result = new WSArrayStruct<wscomplex_t>;
      result->rc = 0;
      result->len = len_out;
      result->data = out_buf;
      return complexarr(result);
   }



  //      float* in_buf = (float*)input;      
      int len_out = (len / 2) + 1; 
           

      // This is the cost of doing things this way.  
      // The input/output buffers must stay constant.
      memcpy(cached_inbuf, input, len * sizeof(float));
      fftwf_execute(cached_plan);
      //      memcpy(output, cached_outbuf, len_out * sizeof(_Complex float));
      return cached_outbuf;
 }



*/





   // [2007.10.28] Porting to new Array format.
   // Could generate this within emit-c.ss using FFTW + codegen for arrays.

   static floatarr ifftC2R(complexarr& input) {
      int len = input->len;
      int len_out = (len - 1) * 2; 

      wscomplex_t*   in_buf  = (wscomplex_t*)input->data; 
      wsfloat_t  *   out_buf = new wsfloat_t[len_out]; // Return a new array with the result.

      //printf(" FFT: %d->%d\n", len, len_out);

      // Inefficient!  This approach makes a new plan every time.
      // Real to complex:
      fftwf_plan plan = fftwf_plan_dft_c2r_1d(len, (fftwf_complex*)in_buf, out_buf, FFTW_ESTIMATE);  
      fftwf_execute(plan);
      fftwf_destroy_plan(plan);           

      //WSArrayStruct<wscomplex_t>* result = (WSArrayStruct<wscomplex_t>*)malloc(sizeof(WSArrayStruct<wscomplex_t>));
      WSArrayStruct<wsfloat_t>* result = new WSArrayStruct<wsfloat_t>;
      result->rc = 0;
      result->len = len_out;
      result->data = out_buf;
      return floatarr(result);
   }



/*
   static boost::shared_ptr< vector< wsfloat_t > >
          ifftC2R(const boost::shared_ptr< vector< wscomplex_t > >& input) {
      int len = (*input).size();
      int len_out = (len - 1) * 2; 

      wscomplex_t* in_buf = new wscomplex_t[len];
      wsfloat_t* out_buf = new wsfloat_t[len_out];
      vector<wsfloat_t>* result = new vector<wsfloat_t>(len_out);

      //printf("   IFFT: %d->%d\n", len, len_out);

      for(int i=0; i<len; i++) in_buf[i] = (*input)[i];

      // Complex to real: DESTROYS INPUT ARRAY:
      fftwf_plan plan = fftwf_plan_dft_c2r_1d(len, (fftwf_complex*)in_buf, out_buf, FFTW_ESTIMATE);      
      fftwf_execute(plan);
      fftwf_destroy_plan(plan);           

      for(int i=0; i<len_out; i++) 
	(*result)[i] = out_buf[i];

      delete in_buf;
      delete out_buf;
      return boost::shared_ptr< vector< wsfloat_t > >( result );
   }

*/
