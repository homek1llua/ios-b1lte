#include <Library/MemoryMapLib.h>

// Taken from the working beyond2ltePkg firmware on the owner's S10 (BOOT dump,
// 2026-11-20). Same Exynos 9820 memory layout per docs/device-facts.md.

STATIC
EFI_MEMORY_REGION_DESCRIPTOR
gMemoryDescriptor[] = {
  // Name, Address, Length, HobOption, ResourceType, ResourceAttribute, MemoryType, ArmAttribute

  // DDR Regions
  {"Lower dynamic guard",   0x80000000, 0x07000000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH},
  {"Samsung U-H EL2",       0x87000000, 0x00200000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_BACK},
  {"Lower dynamic guard",   0x87200000, 0x41E00000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH},
  {"UEFI FD",               0xC9000000, 0x00400000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK},
  {"UEFI Stack",            0xC9400000, 0x00040000, AddMem, SYS_MEM, SYS_MEM_CAP, BsData, WRITE_BACK},
  {"Lower dynamic guard",   0xC9440000, 0x00BC0000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH},
  {"Display Reserved",      0xCA000000, 0x01400000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH},
  {"DXE Heap",              0xCB400000, 0x03C00000, AddMem, SYS_MEM, SYS_MEM_CAP, Conv, WRITE_BACK},
  {"B2L EL2",               0xCF000000, 0x00040000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, ARM_MEMORY_REGION_ATTRIBUTE_UNCACHED_UNBUFFERED},
  {"B2L RT Log",            0xCF040000, 0x00010000, AddMem, SYS_MEM, SYS_MEM_CAP, RtData, WRITE_BACK},
  {"Lower dynamic guard",   0xCF050000, 0x30FB0000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH},
  {"Upper bank guard",      0x880000000, 0x80000000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH},
  {"Upper bank guard",      0x980000000, 0x80000000, AddMem, MEM_RES, SYS_MEM_CAP, Reserv, WRITE_THROUGH},

  // Register Regions
  {"IRAM",                  0x02020000, 0x00018000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"NS_IRAM",               0x02038000, 0x00004000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"Chip Info",             0x10000000, 0x00001000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"WDT CL0",               0x10050000, 0x00001000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"WDT CL2",               0x10060000, 0x00001000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"GICD",                  0x10101000, 0x00001000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"GICC",                  0x10102000, 0x00001000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"PMU",                   0x15860000, 0x00010000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"Decon",                 0x19030000, 0x00010000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"Clock Controller",      0x1A240000, 0x00008000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"UFS UniPro",            0x13D50000, 0x00008000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"UFS HCI",               0x13D60000, 0x00010000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE},
  {"UFS IO Coherency",      0x13C10000, 0x00001000, AddDev, MMAP_IO, UNCACHEABLE, MmIO, DEVICE}
};

VOID
GetMemoryMap (
  OUT EFI_MEMORY_REGION_DESCRIPTOR **MemoryDescriptor,
  OUT UINT8                         *MemoryDescriptorCount)
{
  *MemoryDescriptor      = gMemoryDescriptor;
  *MemoryDescriptorCount = ARRAY_SIZE (gMemoryDescriptor);
}
