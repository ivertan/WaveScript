#!/bin/sh

TEMP="./logs/"

source ../shared.sh

## ================================================================================ ##
echo;echo;echo " *** Running all microbenchmarks  Takes approx ?? minutes. ***"; echo; 

rm -rf $TEMP
mkdir $TEMP

echo "## User time for each benchmark/backend " > RESULTS.txt
echo "Benchmark ChezScheme GCC MLton" >> RESULTS.txt
runallbackends readfile_bigwins   $TEMP 30 
runallbackends readfile_smallwins $TEMP 30 
runallbackends just_timer         $TEMP 35 


