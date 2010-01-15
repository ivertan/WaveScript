
#include <stdlib.h>
#include <stdio.h>
#include "wsq_runtime.h"

// An example demonstrating how to link and use the WSQ runtime system.

#include "port.h"

int main(int argc, char* argv[]) {
    char addr[128];
    //sprintf(addr, "fort2.csail.mit.edu | %d", PORT);
    sprintf(addr, "localhost | %d", PORT);

  WSQ_Init();

  WSQ_BeginTransaction(1001);
    WSQ_BeginSubgraph(101);

      WSQ_AddOp(2, "ReutersSource", "","2", "foobar.schema");
      WSQ_AddOp(3, "ConnectRemoteOut", "2", "", addr); 

    WSQ_EndSubgraph();
  WSQ_EndTransaction();

  sleep(1000);

  WSQ_Shutdown();
  return 0;
}
