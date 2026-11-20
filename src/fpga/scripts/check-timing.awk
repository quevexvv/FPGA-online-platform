# Quartus Prime 23.1 TimeQuest summary records and full report completion.
FILENAME == ARGV[1] {
    if ($0 ~ /^[[:space:]]*$/) next
    if ((state == 0 || state == 2 || state == 3) && $0 ~ /^-+$/) {
        state = (state == 3 ? 6 : state + 1)
    } else if (state == 1 && $0 == "Timing Analyzer Summary") {
        state = 2
    } else if (state == 3 && $0 ~ /^Type[[:space:]]*:[[:space:]]+.+ Model (Setup|Hold|Recovery|Removal|Minimum Pulse Width) '[^']+'$/) {
        if ($0 ~ / Model Setup /) setup = 1
        if ($0 ~ / Model Hold /) hold = 1
        if ($0 ~ / Model Minimum Pulse Width /) pulse = 1
        state = 4
    } else if ((state == 4 && $1 == "Slack" || state == 5 && $1 == "TNS") &&
               NF == 3 && $2 == ":" && $3 ~ /^-?[0-9]+\.[0-9]+$/ && length($3) <= 24) {
        if (state == 4) {
            if (count == 0 || $3 + 0 < min_slack + 0) min_slack = $3
            state = 5
        } else {
            if (count == 0 || $3 + 0 < min_tns + 0) min_tns = $3
            count++
            state = 3
        }
    } else {
        invalid = 1
        exit
    }
    next
}
FNR == 1 && $0 != "Timing Analyzer report for job" { invalid = 1; exit }
/^Info: Quartus Prime Timing Analyzer was successful\. 0 errors, [0-9]+ warnings?[[:space:]]*$/ { completed++ }
END {
    if (invalid || state != 6 || !setup || !hold || !pulse || completed != 1) {
        print "TimeQuest reports are invalid or incomplete"
        exit 2
    }
    printf "TimeQuest: %d checks, minimum slack %s ns, minimum TNS %s ns\n", count, min_slack, min_tns
    if (min_slack + 0 < 0 || min_tns + 0 < 0) exit 1
}
