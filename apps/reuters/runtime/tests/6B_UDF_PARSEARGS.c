
#include <stdio.h>
#include "wsq_runtime.h"

// This test demonstrates the alternative UDF capability with extra argument parsing.

int main(int argc, char* argv[]) 
{
  printf("Launching query through FFI interface.\n");

  // Set output file:
  WSQ_Init("6B_UDF_PARSEARGS.out");
  WSQ_SetQueryName("generated_query_6B");

    WSQ_BeginTransaction(99);
       WSQ_BeginSubgraph(11);
        WSQ_AddOp(1, "RandomSource", "", "100", "10000 |foobar.schema");

	// In this version we give arguments in FULL WaveScript Syntax
	// (e.g. anything that could go in a .ws file).	
        WSQ_AddOp(2, "UDF_PARSEARGS", "100", "200", "6B_UDF_PARSEARGS.ws | myUDF | 39 | fun(x) { x.TIME } ");

	// Three stages of argument parsing:
	// (1) Strings, as passed above from C (and then into Scheme)
        // (2) WaveScript syntax generated [optional parsing here]
	// (3) WaveScript eventually runs, and consumes a runtime
	//     representation of the argument.


        WSQ_AddOp(3, "Printer", "200", "", " [6_UDF] got output: ");
       WSQ_EndSubgraph();
    WSQ_EndTransaction();

    sleep(2);
    printf("\n [6_UDF] Query successfully ran for 3 seconds, shutting down...\n");
    WSQ_Shutdown();
    
    printf(" [6_UDF] Shutdown apparently successful.\n");
    return 0;
}
