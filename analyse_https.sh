#!/bin/bash

# a function to display a progress bar
function ProgressBar {
  let _progress=(${1}*100/${2}*100)/100
  let _done=(${_progress}*4)/10
  let _left=40-$_done
  _fill=$(printf "%${_done}s")
  _empty=$(printf "%${_left}s")
  printf "\rProgress : [${_fill// /\#}${_empty// /-}] ${_progress}%%"
}

tests=1000
myip="192.168.2.15"

# download the needed files if they are not present
if [ ! -f ./goz.txt ]; then
  svn checkout https://github.com/andrewaeva/DGA/trunk/dga_wordlists
  mv dga_wordlists/*txt .
  rm open* others* dga_wordlists/ -Rf
fi

if [ ! -f ./top-1m.csv ]; then
  wget http://s3.amazonaws.com/alexa-static/top-1m.csv.zip
  unzip top-1m.csv.zip
  rm top-1m.csv.zip
fi

echo "========================"
echo "Working with Alexa"
echo "========================"
echo

tcpdump -i enp3s0 -w alexa_https.pcap &
sleep 3

#get the first domains from alexa
head -n $tests top-1m.csv|awk -F',' '{print $2}' > top1K
cnt=0
while read p; do
  ./pydig +https "$p" > /dev/null
  let cnt+=1
  if [ $(( $cnt  % 50 )) -eq 0 ]; then
    sleep .$[ ( $RANDOM % 4 ) + 1 ]s
  fi
  ProgressBar ${cnt} ${tests}
done < top1K
rm top1K

# find the PID of tcpdump
pid=$(sudo ps -e | pgrep tcpdump)
# now kill tcpdump
sleep 2
sudo kill -2 $pid

# now capture traffic for domains from DGAs
echo
echo "========================"
echo "Working with DGA domains"
echo "========================"
echo

for f in *.txt
do
  fname=${f%.*}
  echo "Working with $fname DGA"
  sfx="_https.pcap"
  tcpdump -i enp3s0 -w "$fname$sfx" &
  sleep 3
  cnt=0
  head -n $tests $f > dgatmp
  while read p; do
    ./pydig +https "$p" > /dev/null
    let cnt+=1
    if [ $(( $cnt  % 50 )) -eq 0 ]; then
      sleep .$[ ( $RANDOM % 4 ) + 1 ]s
    fi
    ProgressBar ${cnt} ${tests}
  done < dgatmp

  # find the PID of tcpdump
  pid=$(sudo ps -e | pgrep tcpdump)

  # now kill tcpdump
  sleep 2
  sudo kill -2 $pid
done

rm dgatmp -f

# now create the figures
for f in *.pcap
do
  fname=${f%.*}
  echo "packet,length">$fname.csv
  tshark -r $f -2 -R "ip.dst == $myip" -T fields -E separator=,, -e ip.src -e ip.dst -e frame.len -e _ws.col.Protocol -e _ws.col.Info|grep "Application"|awk -F',' -v OFS=',' '{print NR,$3}'>> $fname.csv
  cp template.tex_ $fname.tex
  sed -i "s/changeme/$fname/g" $fname.tex
  pdflatex $fname.tex
done

# clean up the mess
# leave only the csv and pcap files
exts="aux bbl blg brf idx ilg ind lof log lol lot out toc synctex.gz fls fdb_latexmk txt"
for ext in $exts; do
  rm -f *.$ext
done

mkdir -p figures
mv *pdf figures
mkdir -p backupfiles
mv *pcap backupfiles
mv *csv backupfiles
mv *tex backupfiles
