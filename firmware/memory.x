MEMORY
{
  /* NOTE K = KiBi = 1024 bytes */
  /* 192K total - 4K storage = 188K for program */
  FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 188K
  STORAGE (r) : ORIGIN = 0x0002F000, LENGTH = 4K
  RAM : ORIGIN = 0x20000000, LENGTH = 24K
}

PROVIDE(storage_start = ORIGIN(STORAGE));
PROVIDE(storage_end = ORIGIN(STORAGE) + LENGTH(STORAGE));
PROVIDE(storage_size = LENGTH(STORAGE));
