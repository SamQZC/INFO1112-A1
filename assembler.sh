#!/bin/bash
# INFO1112 A1: assemble .vsc text into binary bytes.
# Generative AI acknowledgement: ChatGPT assisted with requirements,
# code development, debugging, testing and explanations.

# 1. Print an error on STDOUT and stop.
fail() {
    printf '%s\n' "$1"
    exit 1
}

# Read a decimal value into number. The second argument is its upper limit.
parse_decimal() {
    if [[ ! "$1" =~ ^0*[0-9]{1,3}$ ]]; then
        return 1
    fi
    number=$((10#$1))
    if (( number > $2 )); then
        return 1
    fi
    return 0
}

# Store one byte as two hex digits, ready to write after validation.
add_byte() {
    hex=$(printf '%02x' "$1")
    dataArray+=("$hex")
}

# 2. Check the command line and input file (R1-R5).
if (( $# == 0 )); then
    fail 'usage: no argument is provided'
fi
if (( $# > 1 )); then
    fail 'usage: more than one arguments are provided'
fi
inputFile="$1"
if [[ ! -f "$inputFile" ]]; then
    fail 'usage: input is not a file or it does not exist'
fi
if [[ "$inputFile" != *.vsc ]]; then
    fail 'usage: input does not have the extension .vsc'
fi
if [[ ! -s "$inputFile" ]]; then
    fail 'usage: the file is empty – no .bin file is produced'
fi
if [[ ! -r "$inputFile" ]]; then
    fail 'usage: the input file cannot be read'
fi

# Reject a binary NUL character; an ordinary Bash read would discard it.
if IFS= read -r -d '' line < "$inputFile"; then
    fail 'usage: the input file must be text without NUL bytes'
fi

dataArray=()
dataCount=0
lineNumber=0
instructionCount=0
foundQuit=0

# 3. Read the header and static data, then process the instructions.
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    lineNumber=$((lineNumber + 1))

    if (( lineNumber == 1 )); then
        if [[ "$line" != '0' && "$line" != '2' ]]; then
            fail 'usage: the first line must be 0 or 2'
        fi
        dataCount="$line"
        continue
    fi

    if (( lineNumber <= dataCount + 1 )); then
        if ! parse_decimal "$line" 127; then
            fail "usage: line $lineNumber must be an integer from 0 to 127"
        fi
        add_byte "$number"
        continue
    fi

    # No more instructions after QUIT; allow empty lines at the end.
    if (( foundQuit == 1 )); then
        if [[ -n "$line" ]]; then
            fail "usage: unexpected content after QUIT on line $lineNumber"
        fi
        continue
    fi

    # 4. Validate the instruction before splitting its three fields.
    if (( instructionCount >= 100 )); then
        fail 'usage: a program cannot contain more than 100 instructions'
    fi
    if (( ${#line} > 11 )); then
        fail "usage: instruction on line $lineNumber is longer than 11 characters"
    fi
    if (( dataCount == 0 )) && [[ "$line" != 'QUIT,0,0' ]]; then
        fail 'usage: a program with 0 data values must contain QUIT,0,0'
    fi
    if [[ ! "$line" =~ ^[A-Z]+,[0-9]+,[0-9]+$ ]]; then
        fail "usage: invalid instruction format on line $lineNumber"
    fi
    IFS=, read -r instruction register memory <<< "$line"

    if [[ "$instruction" == 'LOAD' ]]; then
        opcode=1
    elif [[ "$instruction" == 'STORE' ]]; then
        opcode=2
    elif [[ "$instruction" == 'ADD' ]]; then
        opcode=3
    elif [[ "$instruction" == 'SUB' ]]; then
        opcode=4
    elif [[ "$instruction" == 'QUIT' ]]; then
        opcode=8
    elif [[ "$instruction" == 'PRINT' ]]; then
        opcode=9
    else
        fail "usage: unknown instruction on line $lineNumber"
    fi

    if ! parse_decimal "$register" 3; then
        fail "usage: register on line $lineNumber must be from 0 to 3"
    fi
    register="$number"
    if ! parse_decimal "$memory" 255; then
        fail "usage: memory address on line $lineNumber must be from 0 to 255"
    fi
    memory="$number"
    if [[ "$instruction" == 'QUIT' && "$line" != 'QUIT,0,0' ]]; then
        fail 'usage: QUIT must be written exactly as QUIT,0,0'
    fi
    if [[ "$instruction" == 'PRINT' ]] && (( memory != 0 )); then
        fail "usage: PRINT on line $lineNumber must have a memory field of 0"
    fi

    # 5. Six opcode bits and two register bits form the first byte.
    firstByte=$((opcode * 4 + register))
    add_byte "$firstByte"
    add_byte "$memory"
    instructionCount=$((instructionCount + 1))
    if [[ "$instruction" == 'QUIT' ]]; then
        foundQuit=1
    fi
done < "$inputFile"

if (( lineNumber < dataCount + 1 )); then
    fail 'usage: the file is missing static data'
fi
if (( foundQuit == 0 )); then
    fail 'usage: the program must end with QUIT,0,0'
fi

# 6. Build escape sequences and write the validated bytes in one batch.
outputFile="${inputFile%.vsc}.bin"
if [[ -L "$outputFile" || "$inputFile" -ef "$outputFile" ]]; then
    fail 'usage: the output path must be a separate regular file'
fi
if [[ -e "$outputFile" && ! -f "$outputFile" ]]; then
    fail 'usage: the output path must be a regular file'
fi
byteEscapes=''
for hex in "${dataArray[@]}"; do
    byteEscapes="$byteEscapes\\x$hex"
done
if ! printf '%b' "$byteEscapes" 2>/dev/null > "$outputFile"; then
    fail 'usage: the output file could not be written'
fi

# 7. Display one lowercase hex byte per line (R6-R7).
if (( dataCount == 0 )); then
    printf '%s\n' 'It is a QUIT program'
else
    printf '%s\n' 'It is an ADD/SUB program'
fi
printf '%s\n' 'The content of the .bin file is'
printf '%s\n' "${dataArray[@]}"
exit 0
