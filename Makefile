#NO_ARDUINO

TEENSY = 40
BUILDDIR = build
BINDIR = bin
TARGET = main
DEFINES = -DARDUINO=10813 -DTEENSYDUINO=154
DEFINES += -DUSB_SERIAL -DLAYOUT_US_ENGLISH -DUSING_MAKEFILE

ifndef NO_ARDUINO
LIBRARYPATH = libraries
ifeq ($(OS),Windows_NT)
	TOOLSPATH = /usr/share/arduino/hardware/tools
	COMPILERPATH = $(TOOLSPATH)/arm/bin
	POSTCOMPILE = "$(TOOLSPATH)/teensy_post_compile.exe"
	REBOOT = "$(TOOLSPATH)/teensy_reboot.exe"
else
	TOOLSPATH = $(abspath tools)
	COMPILERPATH = $(TOOLSPATH)/arm/bin
	POSTCOMPILE = $(TOOLSPATH)/teensy_post_compile
	REBOOT = $(TOOLSPATH)/teensy_reboot
endif

else
COMPILERPATH ?= /usr/bin
endif

CPUOPTIONS = -mthumb
CPPFLAGS = -Wall -g -Os -MMD 
CXXFLAGS = -std=gnu++14 -felide-constructors -fno-exceptions -fno-rtti
ASMFLAGS = -Wall -g -MMD 
CFLAGS =
LDFLAGS = -Os -Wl,--gc-sections
LIBS = -lm -lstdc++

# compiler options specific to teensy version
ifeq ($(TEENSY), 30)
	COREPATH = cores/teensy3
	CPUOPTIONS += -mcpu=cortex-m4
	MCU = MK20DX128
	MCU_LD = mk20dx128.ld
	CORE_SPEED ?= 48000000
	LDFLAGS += -Wl,--defsym=__rtc_localtime=0 --specs=nano.specs
else ifeq ($(TEENSY),$(filter $(TEENSY),31 32))
	COREPATH = cores/teensy3
	CPUOPTIONS += -mcpu=cortex-m4
	MCU = MK20DX256
	MCU_LD = mk20dx256.ld
	CORE_SPEED ?= 72000000
	LDFLAGS += -Wl,--defsym=__rtc_localtime=0 --specs=nano.specs
else ifeq ($(TEENSY), 40)
	COREPATH = cores/teensy4
	CPUOPTIONS += -mcpu=cortex-m7 -mfloat-abi=hard -mfpu=fpv5-d16
	CXXFLAGS += -fpermissive -Wno-error=narrowing
	MCU = IMXRT1062
	MCU_LD = imxrt1062.ld
	CORE_SPEED ?= 600000000
	LDFLAGS += -Wl,--relax
	LIBS += -larm_cortexM7lfsp_math -lstdc++
	DEFINES += -DARDUINO_TEENSY40
else ifeq ($(TEENSY), 41)
	COREPATH = cores/teensy4
	CPUOPTIONS += -mcpu=cortex-m7 -mfloat-abi=hard -mfpu=fpv5-d16
	CXXFLAGS += -fpermissive -Wno-error=narrowing
	MCU = IMXRT1062
	MCU_LD = imxrt1062_t41.ld
	CORE_SPEED ?= 600000000
	LDFLAGS += -Wl,--relax
	LIBS += -larm_cortexM7lfsp_math -lstdc++
	DEFINES += -DARDUINO_TEENSY41
else
	$(error Invalid setting for TEENSY)
endif

CPPFLAGS += $(CPUOPTIONS) -D__$(MCU)__ -DF_CPU=$(CORE_SPEED) $(DEFINES) -Isrc -I$(COREPATH) 
ASMFLAGS += $(CPUOPTIONS) -Isrc -I$(COREPATH)
LDFLAGS += $(CPUOPTIONS) -T$(COREPATH)/$(MCU_LD)

CC = $(COMPILERPATH)/arm-none-eabi-gcc
CXX = $(COMPILERPATH)/arm-none-eabi-g++
AS = $(COMPILERPATH)/arm-none-eabi-as
OBJCOPY = $(COMPILERPATH)/arm-none-eabi-objcopy
SIZE = $(COMPILERPATH)/arm-none-eabi-size

LC_FILES := $(wildcard $(LIBRARYPATH)/*/*.c)
LCPP_FILES := $(wildcard $(LIBRARYPATH)/*/*.cpp)
LASM_FILES := $(wildcard $(LIBRARYPATH)/*/*.S)
TC_FILES := $(wildcard $(COREPATH)/*.c)
TCPP_FILES := $(filter-out $(COREPATH)/main.cpp, $(wildcard $(COREPATH)/*.cpp)) # ignore main.cpp within teensy cores
C_FILES := $(wildcard src/*.c)
CPP_FILES := $(wildcard src/*.cpp)

#INO_FILES := $(wildcard src/*.ino)

L_INC := $(foreach lib,$(filter %/, $(wildcard $(LIBRARYPATH)/*/)), -I$(lib))

SOURCES := $(C_FILES:.c=.o) $(CPP_FILES:.cpp=.o) $(TC_FILES:.c=.o) $(TCPP_FILES:.cpp=.o) $(LC_FILES:.c=.o) $(LCPP_FILES:.cpp=.o) $(LASM_FILES:.S=.o) #$(INO_FILES:.ino=.o)
OBJS := $(foreach src,$(SOURCES), $(BUILDDIR)/$(src))

# the actual makefile rules
all: $(BINDIR)/$(TARGET).hex

post_compile: $(BINDIR)/$(TARGET).hex
	@$(POSTCOMPILE) -file="$(notdir $(basename $<))" -path="$(BINDIR)" -tools="$(TOOLSPATH)"

reboot:
	@-$(REBOOT)

upload: post_compile reboot

$(BUILDDIR)/%.o: %.c
	@echo "[CC]  $<"
	@mkdir -p "$(dir $@)"
	@$(CC) $(CPPFLAGS) $(CFLAGS) $(L_INC) -o "$@" -c "$<"

$(BUILDDIR)/%.o: %.cpp
	@echo "[CXX] $<"
	@mkdir -p "$(dir $@)"
	@$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(L_INC) -o "$@" -c "$<"

$(BUILDDIR)/%.o: %.s
	@echo -n "[ASM] Building"
	@mkdir -p "$(dir $@)"
	@$(AS) $(ASMFLAGS) $(L_INC) -o "$@" -c "$<" 

$(BINDIR)/$(TARGET).elf: $(OBJS) $(LDSCRIPT)
	@echo "[LD]  $@"
	@mkdir -p "$(dir $@)"
	@$(CC) $(LDFLAGS) -o "$@" $(OBJS) $(LIBS)

$(BINDIR)/$(TARGET).hex: $(BINDIR)/$(TARGET).elf
	@echo "[HEX] $@"
	@mkdir -p "$(dir $@)"
	@$(SIZE) $<
	@$(OBJCOPY) -O ihex -R .eeprom $< $@

# compiler generated dependency info
-include $(OBJS:.o=.d)

clean:
	@echo Cleaning...
	@rm -rf "$(BINDIR)"
	@rm -rf "$(BUILDDIR)"
