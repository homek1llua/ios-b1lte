/* SPDX-License-Identifier: BSD-2-Clause
 *
 * Galaxy S10 (beyond1lte) touch power-up for the XNU handoff.
 *
 * B2LInput in the kernel talks to the sec_ts Y771 at hsi2c@104B0000 slave 0x48
 * itself, but only if the firmware left the controller with timings programmed
 * (HSI2C 0x60/0x64 non-zero) and the chip powered and booted. From the board
 * DTB: tsp_io (DVDD, 1.8 V) = S2MPS19 LDO19M, tsp_avdd (AVDD, 3.0 V) = LDO27M,
 * both regulator-boot-on with fixed voltages.
 *
 * This driver only sets the enable bits of those two LDOs (the voltage field
 * programmed by the bootloader is left as it is, and logged), then calls
 * HsI2c->InitBus(10) and gives the chip time to boot. No touch commands.
 */
#include <Uefi.h>
#include <Library/DebugLib.h>
#include <Library/TimerLib.h>
#include <Library/DxeServicesTableLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Protocol/EFISpeedy.h>
#include <Protocol/EFIHsI2c.h>
#include <Protocol/EFIPmicRegulator.h>

#define TOUCH_BUS        10
// PERIC0 sysreg page holding the USI mode registers (USI_HSI2C10 at +0x1C). Upstream
// UsiDxe writes it from InitBus, but nothing maps it; the owner's touch driver did.
#define PERIC0_SYSREG    0x10421000
#define TOUCH_HSI2C_BASE 0x104B0000
#define PMIC_SPEEDY_BUS  0
#define PMIC_PM_ADDR     0x01
#define LDO_CTRL(n)      (0x45 + (n))
#define LDO_DVDD         19
#define LDO_AVDD         27

STATIC
UINT8
ReadLdo (EFI_SPEEDY_PROTOCOL *Speedy, UINT8 Ldo)
{
  UINT8 Value = 0xFF;
  if (Speedy == NULL || EFI_ERROR (Speedy->Read (PMIC_SPEEDY_BUS, PMIC_PM_ADDR, LDO_CTRL (Ldo), &Value))) {
    return 0xFF;
  }
  return Value;
}

EFI_STATUS
EFIAPI
B2LTouchPowerEntry (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE *SystemTable)
{
  EFI_STATUS                   Status, Dvdd = EFI_NOT_STARTED, Avdd = EFI_NOT_STARTED, Init = EFI_NOT_STARTED;
  EFI_PMIC_REGULATOR_PROTOCOL *Regulator = NULL;
  EFI_SPEEDY_PROTOCOL         *Speedy    = NULL;
  EFI_HSI2C_PROTOCOL          *HsI2c     = NULL;
  UINT8                        Before19, Before27;

  DEBUG ((EFI_D_ERROR, "B2L TOUCH PWR: start\n"));
  gBS->LocateProtocol (&gEfiSpeedyProtocolGuid, NULL, (VOID **)&Speedy);
  Before19 = ReadLdo (Speedy, LDO_DVDD);
  Before27 = ReadLdo (Speedy, LDO_AVDD);

  DEBUG ((EFI_D_ERROR, "B2L TOUCH PWR: ldo19=0x%02x ldo27=0x%02x before\n", Before19, Before27));
  Status = gBS->LocateProtocol (&gEfiPmicRegulatorProtocolGuid, NULL, (VOID **)&Regulator);
  if (!EFI_ERROR (Status)) {
    Dvdd = Regulator->SetLdo (ID_S2MPS19, LDO_DVDD, S2MPS_MODE_NORMAL, TRUE);
    MicroSecondDelay (2000);
    Avdd = Regulator->SetLdo (ID_S2MPS19, LDO_AVDD, S2MPS_MODE_NORMAL, TRUE);
    MicroSecondDelay (10000);
  }

  DEBUG ((EFI_D_ERROR, "B2L TOUCH PWR: ldo19 %r ldo27 %r, now 0x%02x 0x%02x; hsi2c10 init next\n",
          Dvdd, Avdd, ReadLdo (Speedy, LDO_DVDD), ReadLdo (Speedy, LDO_AVDD)));
  Status = gDS->AddMemorySpace (EfiGcdMemoryTypeMemoryMappedIo, PERIC0_SYSREG, SIZE_4KB,
                                EFI_MEMORY_UC);
  DEBUG ((EFI_D_ERROR, "B2L TOUCH PWR: map peric0 sysreg add %r\n", Status));
  Status = gDS->SetMemorySpaceAttributes (PERIC0_SYSREG, SIZE_4KB, EFI_MEMORY_UC);
  DEBUG ((EFI_D_ERROR, "B2L TOUCH PWR: map peric0 sysreg attr %r\n", Status));
  Init = EFI_NOT_READY;
  Status = EFI_ERROR (Status) ? Status : gBS->LocateProtocol (&gEfiHsI2cProtocolGuid, NULL, (VOID **)&HsI2c);
  if (!EFI_ERROR (Status)) {
    Init = HsI2c->InitBus (TOUCH_BUS);
  }
  DEBUG ((EFI_D_ERROR, "B2L TOUCH PWR: hsi2c10 init %r\n", Init));

  // sec_ts needs about 70 ms after power-on before its application firmware answers.
  MicroSecondDelay (100000);
  return EFI_SUCCESS;
}
