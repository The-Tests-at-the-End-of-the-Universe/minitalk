#!/bin/bash

# https://developers.redhat.com/blog/2021/04/23/valgrind-memcheck-different-ways-to-lose-your-memory#generating_a_leak_summary
# https://stackoverflow.com/questions/76698927/why-is-valgrind-ignoring-my-error-exitcode-option
# https://www.cyberciti.biz/faq/unix-howto-read-line-by-line-from-file/#google_vignette
# https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash
# https://phoenixnap.com/kb/bash-increment-decrement-variable#:~:text=12%20to%2013.-,Increment%20Bash%20Variable%20with%20%2B%3D%20Operator,assigned%20in%20a%20single%20statement.
# https://www.baeldung.com/linux/bash-variables-division
# https://stackoverflow.com/questions/169511/how-do-i-iterate-over-a-range-of-numbers-defined-by-variables-in-bash

RED="\x1B[31m"
GRN="\x1B[1;32m"
YEL="\x1B[33m"
BLU="\x1B[34m"
MAG="\x1B[35m"
BMAG="\x1B[1;35m"
CYN="\x1B[36m"
BCYN="\x1B[1;36m"
WHT="\x1B[37m"
RESET="\x1B[0m"
LINEP="\033[40G"
FAIL=false
EXIT_FAIL=false
MEMORY_FAIL=false
PID_FAIL=false
OUTPUT_FAIL=false
LOGS=logs/mt_log

make re -C ../../ 
rm -rf logs
mkdir -p logs

input=cases/input

x=0

echo -e "${BCYN}Client${RESET}"
echo -e "input" >> $LOGS
while read -r line; 
do 
	x=$(( $x + 1 ))
	input=$(echo $line | cut -d "," -f 1)
	expected_exc=$(echo $line | cut -d "," -f 2)

	echo -ne "${YEL}$x ${BLU}| ${BMAG}$input ${BLU}|${RESET}"
	echo -e " $x | $input " >> $LOGS

	echo -e "exitcode output " >> $LOGS
	../../build/bin/client $input &>>$LOGS &
	kill $(pgrep client) &>>$LOGS
	ec=$?
	if [ $ec != $expected_exc ] 
	then 
	EXIT_FAIL=true 
	printf "${RED}EXIT FAIL ${RESET}"
	echo -e "exit code vs expected exit code: $ec $expected_exc" >> $LOGS
	fi
	echo -e "valgrind output " >> $LOGS
	valgrind --error-exitcode=42 --leak-check=full --errors-for-leak-kinds=all ../../build/bin/client $input &>> $LOGS &
	kill $(pgrep memcheck) &>>$LOGS
	if [ $? == 42 ] 
	then 
	MEMORY_FAIL=true 
	printf "${RED}MEMORY FAIL ${RESET}" 
	fi

	if [[ $EXIT_FAIL == false && $MEMORY_FAIL == false ]];
	then 
	printf " ✅"
	else 
	printf " ❌"
	FAIL=true
	fi
	EXIT_FAIL=false
	ERROR_FAIL=false
	MEMORY_FAIL=false
	printf "\n"
done < $input

echo -e "${BCYN}Server${RESET}"
echo -ne "${YEL}1 ${BLU}| ${BMAG}print check ${BLU}|${RESET}"
echo -e "1 | print check" >> $LOGS
output=$(../../build/bin/server &> temp.txt) &
sleep 0.1
pid=$(head -n 1 temp.txt)
if [ -z ${pid} ];
then
PRINT_FAIL=true
FAIL=true
printf "${RED}PRINT FAIL ${RESET}"
echo -e "pid did not print" >> $LOGS
printf " ❌\n"
else
	printf " ✅\n"
fi
echo $pid >> $LOGS

echo -ne "${YEL}2 ${BLU}| ${BMAG}pid check ${BLU}|${RESET}"
echo -e "2 | pid check" >> $LOGS
if ps -p $pid >> $LOGS
then
	printf " ✅\n"
else 
PID_FAIL=true
FAIL=true
printf "${RED}PID FAIL ${RESET}"
echo -e "pid is not of the correct process" >> $LOGS
printf " ❌\n"
fi
kill $(pgrep server) &>>$LOGS

echo -ne "${YEL}3 ${BLU}| ${BMAG}memory check ${BLU}|${RESET}"
valgrind --error-exitcode=42 --leak-check=full --errors-for-leak-kinds=all ../../build/bin/server &>> $LOGS &
kill $(pgrep memcheck) &>>$LOGS
if [ $? == 42 ] 
then 
MEMORY_FAIL=true 
printf "${RED}MEMORY FAIL ${RESET}" 
printf " ❌\n"
else
	printf " ✅\n"
fi
rm -rf temp.txt


echo -e "${BCYN}Client-Server${RESET}"
files=( cases/*.txt )
files=$(echo "${files[6]}" "${files[5]}" "${files[4]}" "${files[3]}" "${files[2]}" "${files[1]}" "${files[0]}")
for file in $files
do
echo -ne "${YEL}$file ${BLU}| ${RESET}"
input=$(head -n 1 $file)
valgrind --error-exitcode=42 --leak-check=full --errors-for-leak-kinds=all ../../build/bin/server &> server.txt &
server_pid=$!
sleep 0.5
pid=$( tail -n 1 server.txt )
valgrind --error-exitcode=42 --leak-check=full --errors-for-leak-kinds=all ../../build/bin/client $pid "$input" &> $LOGS &
client_pid=$!
wait $client_pid
if [ $? == 42 ] 
then 
MEMORY_FAIL=true 
printf "${RED} CLIENT MEMORY FAIL ${RESET}" 
echo -e "client memory exit code $?" >> $LOGS
fi
MEMORY_FAIL=false 
kill $server_pid &>>$LOGS
if [ $? == 42 ] 
then 
MEMORY_FAIL=true 
printf "${RED} SERVER MEMORY FAIL ${RESET}" 
echo -e "server memory exit code $?" >> $LOGS

fi
start=$(cat server.txt | grep -n "^$server_pid" | cut -d ':' -f1)
end=$(cat server.txt | grep -n "^Server" | cut -d ':' -f1)
end=$(( $end - 1 ))
dif=$(($end-$start))
result=$(head -n $end server.txt | tail -n $dif)
if [[ $result != $input ]] 
then 
OUTPUT_FAIL=true 
printf "${RED} SERVER OUTPUT FAIL ${RESET}" 
echo -e "$(diff  <(echo $input ) <(echo $result))" >> $LOGS
fi
if [[ $OUTPUT_FAIL == false && $MEMORY_FAIL == false ]];
then 
printf " ✅"
else 
printf " ❌"
FAIL=true
fi
OUTPUT_FAIL=false
MEMORY_FAIL=false
printf "\n"
done

rm -rf server.txt
rm -rf client.txt

if [ $FAIL = true ];
then 
echo -e "${RED}Check $LOGS ${RESET}"
exit 1
else 
echo -e "${GRE}Congratulations, all tests are succesfull :)${RESET}"
rm -rf logs
fi
