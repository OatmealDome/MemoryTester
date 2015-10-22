#pragma once

#include <cstddef>
#include <cstdlib>
#include <set>
#include <string>

typedef uint8_t  u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

typedef int8_t  s8;
typedef int16_t s16;
typedef int32_t s32;
typedef int64_t s64;

#define nullptr NULL

#define ROUND_UP_POW2(X) RUP2__(X)
#define RUP2__(X) (RUP2_1(X) + 1)
#define RUP2_1(X) (RUP2_2(X) | (RUP2_2(X) >> 16))
#define RUP2_2(X) (RUP2_3(X) | (RUP2_3(X) >> 8))
#define RUP2_3(X) (RUP2_4(X) | (RUP2_4(X) >> 4))
#define RUP2_4(X) (RUP2_5(X) | (RUP2_5(X) >> 2))
#define RUP2_5(X) (RUP2_6(X) | (RUP2_6(X) >> 1))
#define RUP2_6(X) ((X) - 1)


class MemArena
{
public:
    void GrabSHMSegment(size_t size);
    void ReleaseSHMSegment();
    void *CreateView(s64 offset, size_t size, void *base = nullptr);
    void ReleaseView(void *view, size_t size);
    
    // This finds 1 GB in 32-bit, 16 GB in 64-bit.
    static u8 *FindMemoryBase();
    //private:
    int fd;
};

struct MemoryView
{
    u8** out_ptr;
    u64 virtual_address;
    u32 size;
    u32 flags;
    void* mapped_ptr;
    void* view_ptr;
    u32 shm_position;
};

enum {
    MV_MIRROR_PREVIOUS = 1,
    MV_FAKE_VMEM = 2,
    MV_WII_ONLY = 4,
};

enum
{
    // RAM_SIZE is the amount allocated by the emulator, whereas REALRAM_SIZE is
    // what will be reported in lowmem, and thus used by emulated software.
    // Note: Writing to lowmem is done by IPL. If using retail IPL, it will
    // always be set to 24MB.
    REALRAM_SIZE  = 0x01800000,
    RAM_SIZE      = ROUND_UP_POW2(REALRAM_SIZE),
    RAM_MASK      = RAM_SIZE - 1,
    FAKEVMEM_SIZE = 0x02000000,
    FAKEVMEM_MASK = FAKEVMEM_SIZE - 1,
    L1_CACHE_SIZE = 0x00040000,
    L1_CACHE_MASK = L1_CACHE_SIZE - 1,
    IO_SIZE       = 0x00010000,
    EXRAM_SIZE    = 0x04000000,
    EXRAM_MASK    = EXRAM_SIZE - 1,
    
    ADDR_MASK_HW_ACCESS = 0x0c000000,
    ADDR_MASK_MEM1      = 0x20000000,
    
#if _ARCH_32
    MEMVIEW32_MASK  = 0x3FFFFFFF,
#endif
};

void redirectLogOutput();
u8 *MemoryMap_Setup(MemoryView *views, int num_views, u32 flags, MemArena *arena);
void MemoryMap_Shutdown(MemoryView *views, int num_views, u32 flags, MemArena *arena);
inline std::string format(const char* fmt, ...);
