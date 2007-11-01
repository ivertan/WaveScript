#!/bin/sh


START=`pwd`
TEMP="$START/logs/"

source ../shared.sh

## ================================================================================ ##
echo;echo;echo " *** Running all application benchs.  Takes approx ?? minutes. ***"; echo; 

rm -rf $TEMP
mkdir $TEMP


## ================================================================================ ##
##   MARMOT BENCH
## ================================================================================ ##

echo "  Making a big enough audio file."; echo
cd "$REGIMENTD/apps/marmot";
(rm -f 6sec_marmot_sample.raw)
(./download_small_sample_data)
(cp 6sec_marmot_sample.raw temp.raw;)
(cat temp.raw >> 6sec_marmot_sample.raw)
(cat temp.raw >> 6sec_marmot_sample.raw)
(cat temp.raw >> 6sec_marmot_sample.raw)
(cat temp.raw >> 6sec_marmot_sample.raw)
(cat temp.raw >> 6sec_marmot_sample.raw)
(cat temp.raw >> 6sec_marmot_sample.raw)

echo "## Running original marmot app. " > RESULTS.txt
print_results_header
runallbackends run_first_phase $TEMP 1 5

cd "$START"
mv "$REGIMENTD/apps/marmot/RESULTS.txt" ./

cp RESULTS.txt marmot.txt
echo '\begin{verbatim}' > marmot.tex
cat marmot.txt         >> marmot.tex
echo '\end{verbatim}'  >> marmot.tex


## ================================================================================ ##
##   OTHER MARMOT CONFIGS (Optimizations)
## ================================================================================ ##

## TODO


## ================================================================================ ##
##   STOCKTICKS
## ================================================================================ ##

## (NEEDS TO BE FIXED UNDER C++)
## MLton has no hash table support
export OMITMLTON="true"
## TODO
unset OMITMLTON

## ================================================================================ ##
##   PIPELINE
## ================================================================================ ##

## TODO



## ================================================================================ ##
##   POTHOLES
## ================================================================================ ##

## TODO

