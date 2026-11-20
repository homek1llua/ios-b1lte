// SPDX-License-Identifier: BSD-2-Clause-Patent
// Read the XNU payload from an Android v1 BOOT partition through firmware UFS.
#include "BootPayload.h"
#include "BootMetadata.h"
#include "BootDevicePath.h"
#include <Protocol/BlockIo.h>
#include <Protocol/DiskIo.h>
#include <Protocol/PartitionInfo.h>
#include <Protocol/DevicePath.h>
#include <Library/DevicePathLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>

#define PAYLOAD_LIMIT (128U * 1024U * 1024U)
#define PAYLOAD_HEADER_SIZE 320U
STATIC UINT32 mBootUfsLun = MAX_UINT32;

EFI_STATUS B2lGetBootUfsLun(UINT32 *Lun) {
  if (Lun == NULL) return EFI_INVALID_PARAMETER;
  if (mBootUfsLun > 7) return EFI_NOT_FOUND;
  *Lun = mBootUfsLun;
  return EFI_SUCCESS;
}

STATIC UINT32 Le32(CONST UINT8 *P) {
  return (UINT32)P[0] | (UINT32)P[1] << 8 | (UINT32)P[2] << 16 | (UINT32)P[3] << 24;
}
STATIC UINT64 Le64(CONST UINT8 *P) {
  return (UINT64)Le32(P) | (UINT64)Le32(P + 4) << 32;
}

EFI_STATUS B2lLoadBootPayload(VOID **Kernel, UINTN *KernelSize, UINT8 Seed[B2L_BOOT_SEED_SIZE], UINT8 WifiMac[6]) {
  EFI_HANDLE *Handles = NULL;
  UINTN Count = 0;
  EFI_STATUS Status;
  if (Kernel == NULL || KernelSize == NULL || Seed == NULL || WifiMac == NULL) return EFI_INVALID_PARAMETER;
  ZeroMem(WifiMac, B2L_WIFI_MAC_BYTES);
  *Kernel = NULL;
  *KernelSize = 0;
  mBootUfsLun = MAX_UINT32;
  Status = gBS->LocateHandleBuffer(ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &Count, &Handles);
  if (EFI_ERROR(Status)) return Status;
  Status = EFI_NOT_FOUND;
  UINTN Gpt = 0, BootNamed = 0;
  for (UINTN Index = 0; Index < Count; Index++) {
    EFI_BLOCK_IO_PROTOCOL *Block;
    EFI_DISK_IO_PROTOCOL *Disk;
    EFI_PARTITION_INFO_PROTOCOL *Partition;
    UINT8 Header[48], Payload[PAYLOAD_HEADER_SIZE];
    UINT32 Page, MediaId;
    UINT64 Offset, KernelOffset, Length, Capacity;
    VOID *Buffer;
    EFI_STATUS ReadStatus;
    if (EFI_ERROR(gBS->HandleProtocol(Handles[Index], &gEfiBlockIoProtocolGuid, (VOID **)&Block)) ||
        !Block->Media->MediaPresent || !Block->Media->LogicalPartition ||
        EFI_ERROR(gBS->HandleProtocol(Handles[Index], &gEfiDiskIoProtocolGuid, (VOID **)&Disk)) ||
        EFI_ERROR(gBS->HandleProtocol(Handles[Index], &gEfiPartitionInfoProtocolGuid, (VOID **)&Partition)) ||
        Partition->Type != PARTITION_TYPE_GPT) continue;
    Gpt++;
    if (CompareMem(Partition->Info.Gpt.PartitionName, L"BOOT", sizeof(L"BOOT")) != 0 &&
        CompareMem(Partition->Info.Gpt.PartitionName, L"boot", sizeof(L"boot")) != 0) continue;
    BootNamed++;
    Print(L"B2L: BOOT candidate %u: block %u bytes, last LBA %lu\r\n", (UINT32)BootNamed,
          Block->Media->BlockSize, Block->Media->LastBlock);
    // Reject overflow before converting LastBlock into a byte capacity.
    if (Block->Media->BlockSize == 0 || Block->Media->LastBlock == MAX_UINT64 ||
        Block->Media->LastBlock + 1 > MAX_UINT64 / Block->Media->BlockSize) continue;
    Capacity = (Block->Media->LastBlock + 1) * Block->Media->BlockSize;
    MediaId = Block->Media->MediaId;
    ReadStatus = Disk->ReadDisk(Disk, MediaId, 0, sizeof(Header), Header);
    if (EFI_ERROR(ReadStatus)) { Print(L"B2L:   header read failed: %r\r\n", ReadStatus); continue; }
    if (CompareMem(Header, "ANDROID!", 8) != 0) { Print(L"B2L:   no ANDROID! header\r\n"); continue; }
    Page = Le32(Header + 36);
    // First recognize only a well-bounded Android header before probing payload.
    if (Le32(Header + 40) != 1 || Page < 2048 || Page > 65536 || (Page & (Page - 1)) != 0 ||
        Le32(Header + 16) != 0 || Le32(Header + 24) != 0) {
      Print(L"B2L:   header rejected: version %u page %u ramdisk %u second %u\r\n",
            Le32(Header + 40), Page, Le32(Header + 16), Le32(Header + 24));
      continue;
    }
    Offset = Page + (((UINT64)Le32(Header + 8) + Page - 1) & ~((UINT64)Page - 1));
    if (Offset > Capacity || sizeof(Payload) > Capacity - Offset) { Print(L"B2L:   trailer offset %lu beyond %lu\r\n", Offset, Capacity); continue; }
    ReadStatus = Disk->ReadDisk(Disk, MediaId, Offset, sizeof(Payload), Payload);
    if (EFI_ERROR(ReadStatus)) { Print(L"B2L:   trailer read at %lu failed: %r\r\n", Offset, ReadStatus); continue; }
    if (CompareMem(Payload, "B2LXNU01", 8) == 0) {
      Print(L"B2L: legacy BOOT payload has only 64 seed bytes; repackage B2LXNU02 with 256 bytes.\r\n");
      Status = EFI_COMPROMISED_DATA;
      break;
    }
    if (CompareMem(Payload, "B2LXNU02", 8) != 0) { Print(L"B2L:   no B2LXNU02 at offset %lu\r\n", Offset); continue; }
    // Once our magic is present, corruption must not silently select another OS.
    Status = EFI_COMPROMISED_DATA;
    KernelOffset = Le64(Payload + 24);
    Length = Le64(Payload + 16);
    if (Le32(Payload + 8) != 2 || Le32(Payload + 12) != PAYLOAD_HEADER_SIZE ||
        KernelOffset != PAYLOAD_HEADER_SIZE || Length < 4096 || Length > PAYLOAD_LIMIT ||
        KernelOffset > Capacity - Offset || Length > Capacity - Offset - KernelOffset) break;
    // Decode only after recognizing and bounding our complete BOOT header.
    UINT8 CandidateMac[B2L_WIFI_MAC_BYTES];
    if (b2l_boot_wifi_decode(Payload + 32 + B2L_BOOT_SEED_SIZE, CandidateMac) < 0) break;
    Buffer = AllocatePool((UINTN)Length);
    if (Buffer == NULL) { Status = EFI_OUT_OF_RESOURCES; break; }
    ReadStatus = Disk->ReadDisk(Disk, MediaId, Offset + KernelOffset, (UINTN)Length, Buffer);
    if (EFI_ERROR(ReadStatus)) { Print(L"B2L:   kernel read (%lu bytes) failed: %r\r\n", Length, ReadStatus); FreePool(Buffer); Status = ReadStatus; break; }
    if (Le32(Buffer) != 0xfeedfacf || Le32((UINT8 *)Buffer + 4) != 0x0100000c) {
      FreePool(Buffer);
      break;
    }
    CopyMem(Seed, Payload + 32, B2L_BOOT_SEED_SIZE);
    CopyMem(WifiMac, CandidateMac, B2L_WIFI_MAC_BYTES);
    *Kernel = Buffer;
    *KernelSize = (UINTN)Length;
    EFI_DEVICE_PATH_PROTOCOL *Path;
    if (!EFI_ERROR(gBS->HandleProtocol(Handles[Index], &gEfiDevicePathProtocolGuid, (VOID **)&Path))) {
      UINTN PathSize = GetDevicePathSize(Path);
      UINT32 Lun;
      if (b2l_boot_ufs_lun(Path, PathSize, &Lun) == 0) mBootUfsLun = Lun;
    }
    Print(L"B2L: read %u kernel bytes from BOOT trailer payload\r\n", (UINT32)Length);
    Status = EFI_SUCCESS;
    break;
  }
  if (Status == EFI_NOT_FOUND)
    Print(L"B2L: no BOOT payload: %u block devices, %u GPT partitions, %u named BOOT\r\n",
          (UINT32)Count, (UINT32)Gpt, (UINT32)BootNamed);
  FreePool(Handles);
  return Status;
}
