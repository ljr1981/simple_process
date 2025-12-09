#!/bin/bash
# build.sh - Build and test script for simple_* projects
#
# Usage: ./build.sh [options]
#
# Options:
#   -c, --compile    Compile only (freeze, no tests)
#   -t, --test       Compile and run tests (default)
#   -f, --finalize   Finalize compile (C compile)
#   -h, --help       Show this help
#
# Examples:
#   ./build.sh           # Compile and run tests
#   ./build.sh -c        # Just freeze compile
#   ./build.sh -f        # Finalize only (assumes already frozen)

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME=$(basename "$SCRIPT_DIR")
PROJECT_UPPER=$(echo "$PROJECT_NAME" | tr '[:lower:]' '[:upper:]')

# EiffelStudio paths
EC_EXE="/c/Program Files/Eiffel Software/EiffelStudio 25.02 Standard/studio/spec/win64/bin/ec.exe"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Defaults
MODE="test"  # compile, test, finalize

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--compile)
            MODE="compile"
            shift
            ;;
        -t|--test)
            MODE="test"
            shift
            ;;
        -f|--finalize)
            MODE="finalize"
            shift
            ;;
        -h|--help)
            sed -n '2,14p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set environment variable for this project
export "$PROJECT_UPPER"="$SCRIPT_DIR"
echo -e "${BLUE}[$PROJECT_NAME]${NC} $PROJECT_UPPER=$SCRIPT_DIR"

# Find ECF file
ECF=""
if [ -f "$SCRIPT_DIR/$PROJECT_NAME.ecf" ]; then
    ECF="$SCRIPT_DIR/$PROJECT_NAME.ecf"
else
    ECF=$(ls "$SCRIPT_DIR"/*.ecf 2>/dev/null | head -1)
fi

if [ -z "$ECF" ] || [ ! -f "$ECF" ]; then
    echo -e "${RED}ERROR: No ECF file found${NC}"
    exit 1
fi

# Find test target
TEST_TARGET="${PROJECT_NAME}_tests"
if ! grep -q "target name=\"$TEST_TARGET\"" "$ECF" 2>/dev/null; then
    # Try to find any test target
    TEST_TARGET=$(grep -oP 'target name="\K[^"]*_tests' "$ECF" | head -1)
fi

if [ -z "$TEST_TARGET" ]; then
    echo -e "${YELLOW}WARNING: No test target found in ECF${NC}"
    if [ "$MODE" = "test" ]; then
        MODE="compile"
        echo "Falling back to compile-only mode"
    fi
fi

cd "$SCRIPT_DIR"

case $MODE in
    compile)
        echo -e "${BLUE}Freeze compiling...${NC}"
        "$EC_EXE" -batch -config "$ECF" -target "$TEST_TARGET" -freeze 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Freeze compile successful${NC}"
        else
            echo -e "${RED}Freeze compile failed${NC}"
            exit 1
        fi
        ;;
    
    finalize)
        echo -e "${BLUE}Finalizing (C compile)...${NC}"
        "$EC_EXE" -batch -config "$ECF" -target "$TEST_TARGET" -c_compile 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Finalize successful${NC}"
        else
            echo -e "${RED}Finalize failed${NC}"
            exit 1
        fi
        ;;
    
    test)
        echo -e "${BLUE}Compiling and running tests...${NC}"
        
        # Full compile (freeze + C compile)
        "$EC_EXE" -batch -config "$ECF" -target "$TEST_TARGET" -c_compile 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Compilation failed${NC}"
            exit 1
        fi
        
        # Find and run the executable
        EXE_PATH="$SCRIPT_DIR/EIFGENs/$TEST_TARGET/W_code/${PROJECT_NAME}.exe"
        if [ ! -f "$EXE_PATH" ]; then
            # Try alternate naming
            EXE_PATH=$(find "$SCRIPT_DIR/EIFGENs/$TEST_TARGET/W_code" -maxdepth 1 -name "*.exe" 2>/dev/null | head -1)
        fi
        
        if [ -f "$EXE_PATH" ]; then
            echo -e "${BLUE}Running tests...${NC}"
            "$EXE_PATH"
            TEST_RESULT=$?
            if [ $TEST_RESULT -eq 0 ]; then
                echo -e "${GREEN}Tests passed${NC}"
            else
                echo -e "${RED}Tests failed (exit code: $TEST_RESULT)${NC}"
                exit $TEST_RESULT
            fi
        else
            echo -e "${YELLOW}WARNING: Executable not found at expected path${NC}"
            echo "Expected: $EXE_PATH"
            exit 1
        fi
        ;;
esac

echo -e "${GREEN}Done.${NC}"
