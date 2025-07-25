#------------------------------------------------#
ifeq ($(TOOLSDIR),)
	ifneq ($(DEVKITARM),)
		TOOLSDIR := $(DEVKITARM)
	else
		$(error devKitARM not found, and TOOLSDIR not defined.)
	endif
endif
#------------------------------------------------#
PATH       := $(TOOLSDIR)/bin:$(PATH)
RELEASEDIR := $(CURDIR)/lib
#------------------------------------------------#

SOURCES  := source
INCLUDES := include
BUILD    := build
TARGET   := $(RELEASEDIR)/libusge.a

#------------------------------------------------#

ARCHCROSS := arm-none-eabi-
ARCHFLAGS := -mcpu=arm7tdmi
ARCHFLAGS += -mthumb-interwork -mthumb
ARCHFLAGS += -ffunction-sections -fdata-sections

INCLUDEFLAGS := $(foreach dir, $(INCLUDES), -I$(dir))

GCCFLAGS := -Wall -Wextra -Wundef
CCFLAGS  := $(GCCFLAGS) $(ARCHFLAGS) $(INCLUDEFLAGS) -Os
CXXFLAGS := $(CCFLAGS)
ASFLAGS  := $(GCCFLAGS) $(ARCHFLAGS) $(INCLUDEFLAGS) -x assembler-with-cpp

CFILES   := $(foreach dir, $(SOURCES), $(wildcard $(dir)/*.c))
CXXFILES := $(foreach dir, $(SOURCES), $(wildcard $(dir)/*.cpp))
SFILES   := $(foreach dir, $(SOURCES), $(wildcard $(dir)/*.s))
OFILES   := $(addprefix $(BUILD)/, $(addsuffix .o, $(CFILES) $(CXXFILES) $(SFILES)))
DFILES   := $(OFILES:.o=.d)

#------------------------------------------------#

CC  := $(ARCHCROSS)gcc
CXX := $(ARCHCROSS)g++
AS  := $(ARCHCROSS)gcc
AR  := $(ARCHCROSS)ar

#------------------------------------------------#

all : $(TARGET)

$(TARGET) : $(OFILES) | $(RELEASEDIR) $(BUILD)
	@echo Building library $@
	@$(AR) cr $@ $^

$(BUILD)/%.c.o : %.c | $(BUILD)
	@echo $<
	@mkdir -p $(dir $@)
	@$(CC) $(CCFLAGS) -MD -MP -MF $(BUILD)/$<.d -c -o $@ $<

$(BUILD)/%.cpp.o : %.cpp | $(BUILD)
	@echo $<
	@mkdir -p $(dir $@)
	@$(CXX) $(CXXFLAGS) -MD -MP -MF $(BUILD)/$<.d -c -o $@ $<

$(BUILD)/%.s.o : %.s | $(BUILD)
	@echo $<
	@mkdir -p $(dir $@)
	@$(AS) $(ASFLAGS) -MD -MP -MF $(BUILD)/$<.d -Wa,-I$(dir $<) -c -o $@ $<

$(BUILD):; @mkdir -p $@

$(RELEASEDIR):; @mkdir -p $@

-include $(DFILES)

#------------------------------------------------#

.phony : clean

clean:
	rm -rf $(BUILD)

#------------------------------------------------#
