

#set terminal pdf
set terminal postscript color

#set boxwidth 0.9 absolute
#set style fill  solid 1.00 border -1
#set style histogram clustered gap 1 title  offset character 0, 0, 0
#set datafile missing '-'
#set style data histograms
#set xtics border in scale 1,0.5 nomirror rotate by -45  offset character 0, 0, 0 
#set xtics border in scale 1,0.5 nomirror 

# plot 'RESULTS.txt' using 2:xtic(1) title col, '' using 3 title col, '' using 4 title col
plot \
     'temp/list-iu-match.dat' using 2:3 title 1 with lp \
   , 'temp/list-rn-match.dat' using 2:3 title 1 with lp \
   , 'temp/list-cond.dat'     using 2:3 title 1 with lp \
   , 'temp/vector-iu-match.dat' using 2:3 title 1 with lp \
   , 'temp/vector-rn-match.dat' using 2:3 title 1 with lp \
   , 'temp/vector-cond.dat'     using 2:3 title 1 with lp \
   , 'temp/record-predicates.dat' using 2:3 title 1 with lp \
   , 'temp/constant-dispatch.dat' using 2:3 title 1 with lp \
   , 'temp/log-dispatch.dat'      using 2:3 title 1 with lp \

# grep record-predicates $FILE > temp/record-predicates.dat
# grep log-dispatch      $FILE > temp/log-dispatch.dat
