#!/bin/bash

#Process:
#The first step was getting the python code into bash for extracting
#the IP addresses out of the original file. I found out how to embed
#python code and wrote the other 2 functions in python. The next step
#was to remove the ports from the comma delimited IP address file. I wrote
#a script in python and embedded it into a function called removePorts. The
#next step was to remove the duplicate IP addresses from the new ip file. 
#For this, I read the file line by line and inserted the IP addresses into 
#a set, since a set cannot have duplicates, this automatically solved that
#problem. At this point I had the unique IP address file, so it was time to
#move on to the gnuplot portion. The first thing I did, was use an associative
#array to store the unique ip addresses as the key, and the number of 
#occurrences as the value. I did this by looping through the unique IP file and
#running a grep on each unique IP to see how many times it occurred in the big
#IP script with 2,437 IP addresses. After this, I looped through the 
#associative array and ran 1 curl and 1 read per unique IP address, with a 
#500 ms delay. I chose 500 ms because the api allows 10,000 API calls per hour,
#so 10,000/60/60 is about 2.78 calls per second. I chose 2 calls per second to be 
#on the safe side. In this loop I append the coordinates, occurrences for each 
#ip address, the city, country, and the IP address into a file. I also append
#the ip address and the number of occurrences comma delimited in another file 
#and sort that after the loop. With the coordinates and occurrences, I append
#the gnuplot script with a conditional gnuplot statement that plots each IP 
#address on the world map based on how many instances of that ip address 
#appeared in the original file. I create a separate file just for the 
#customer's location as well. After all this is done, the script runs the 
#gnuplot command and generates the image file.

uniqueIpFile="uniqueip.txt"
bigFile="InputFile.txt"
declare -A occurrenceMap

function extractIpAddresses {
	python - <<END
import re
# Regular Expression
pattern = re.compile('(ALLOW TCP | ALLOW UDP )([0-9]{1,3}\.[0-9]{1,3}\.'
'[0-9]{1,3}\.[0-9]{1,3}):[\d]{1,5}[\s]->[\s][0-9]{1,3}\.[0-9]{1,3}\.'
'[0-9]{1,3}\.[0-9]{1,3}:([0-9]{1,5})')
#-------------------------------------------------------------------------------
#Opens input and output files, searches for the pattern in the input file line 
#by line If the pattern is found, it concatenates the ip, a comma, and the port
#into a string, and stores it in myString with a new line. It then writes 
#myString into the output folder. Repeats until it reaches end of file.
#It then closes both files.
#-------------------------------------------------------------------------------
with open("Router_Security_Notifications.txt", 'r') as file, \
        open("InputFile.txt", 'w') as file2:
    line = file.readline()
    while line:
        line = file.readline()
        m = re.search(pattern, line)
        if m:
            myString = m.group(2) + ',' + m.group(3)+'\n'
            file2.writelines(myString)

file.close()
file2.close()
END
}
function removePorts {
	python -<<END
import re
#Regular Expression
pattern = re.compile('(,[0-9]{1,})')
with open('InputFile.txt', 'r') as file :
  filedata = file.read()

# Replace the target string
filedata = re.sub(pattern,'',filedata)

# Write the file out again
with open('InputFile.txt', 'w') as file:
  file.write(filedata)
END
}
function removeDuplicateIpAddresses {
	python -<<END
#I use the set data structure for this since it allows no duplicates.
ip_set = set()
with open("InputFile.txt",'r') as file, \
	open("uniqueip.txt",'w') as file2:
	line = file.readline()
	while line:
		line = file.readline()
		ip_set.add(line)
	for val in ip_set:
		file2.writelines(val)
END
}

extractIpAddresses
removePorts
removeDuplicateIpAddresses
while IFS= read -r line
do 
	occurrences="$(grep -o $line $bigFile | wc -l)"
	occurrenceMap+=([$line]=$occurrences)
done < "$uniqueIpFile"
for i in "${!occurrenceMap[@]}"
do
	sleep .5
	REPLY=$(curl -s https://json.geoiplookup.io/$i)
	read -r LON LAT CITY COUNTRY IP <<<$(echo $REPLY | jq -r '.|
	"\(.longitude) \(.latitude) \(.city) \(.country_name) \(.ip)"')
	echo $LON $LAT ${occurrenceMap[${i}]} $CITY $COUNTRY $IP >> "ip.txt"
	echo $i,${occurrenceMap[$i]} >> "sortedIP.txt"
done
sort -t, -k 2,2nr  "sortedIP.txt" -o "sortedIP.txt"
echo -122.4816 37.6196 >> "customer_location.cor"	
#Sorry for the last block

echo ' 
set terminal pngcairo transparent enhanced font "arial,10"\
 fontscale 1.0 size 1200, 800 
set output "output.png"
set format x "%D %E" geographic
set format y "%D %N" geographic
unset key
set style data lines
set yzeroaxis
set title "Gnuplot Correspondences\ngeographic coordinate system" 
set xrange [ -180.000 : 180.000 ] noreverse nowriteback
set x2range [ * : * ] noreverse writeback
set yrange [ -90.0000 : 90.0000 ] noreverse nowriteback
set y2range [ * : * ] noreverse writeback
set zrange [ * : * ] noreverse writeback
set cbrange [ * : * ] noreverse writeback
set rrange [ * : * ] noreverse writeback
set key outside Left title "Frequencies" box 3
NO_ANIMATION = 1
## Last datafile plotted: "world.cor"



plot "world_10m.txt" with lines lc rgb "blue" notitle, "ip.txt" u \
(10 > $3 ? $1 : 1/0):(10 > $3 ? $2 : 1/0) with points lt rgb "#FF0000" \
pt 4 title "Less than 10 hits", "ip.txt" u (20 > $3 && 10 <= $3 ? $1 : 1/0):\
(20 > $3 && 10 <=$3 ? $2 : 1/0) with points lt rgb "#FF7F00" pt 4 title\
 "10-19 hits","ip.txt" u (30 > $3 && $3 >= 20 ? $1 : 1/0):\
(30 > $3 && $3 >= 20 ? $2 : 1/0) with points lt rgb "#FFFF00" pt 4 \
title "20-39 hits","ip.txt" u (40 > $3 && $3 >= 30 ? $1 : 1/0):\
(50 > $3 && $3 >= 40 ? $2 : 1/0) with points lt rgb "#00FF00" pt 4 title \
"40-49 hits", "ip.txt" u (60 > $3 && $3 >= 50 ? $1 : 1/0):\
(60 > $3 && $3 >= 50 ? $2 : 1/0) with points lt rgb "#0000FF" pt 4 title\
 "50-59 hits", "ip.txt" u (70 > $3 && $3 >= 60 ? $1 : 1/0):\
(70 > $3 && $3 >= 60 ? $2 : 1/0) with points lt rgb "#4B0082" pt 4 title\
 "60-69 hits", "ip.txt" u ($3 >= 70 ? $1 : 1/0):($3 >= 70 ? $2 : 1/0) \
with points lt rgb "#8F00FF" pt 4 title "70 or greater hits",\
"customer_location.cor" with points lt 9 pt 7 title "Customer Location" '\
>> 'finalGnuPlotScript.gnuplot'
gnuplot finalGnuPlotScript.gnuplot
