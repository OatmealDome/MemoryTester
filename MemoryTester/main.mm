//
//  main.m
//  MemoryTester
//
//  Created by mac on 2015-10-21.
//  Copyright © 2015 OatmealDome. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

#include "main.h"
#include <cstddef>
#include <cstdlib>
#include <set>
#include <string>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

static MemoryView views[] =
{
    {nullptr,      0x200000000, RAM_SIZE,     MV_MIRROR_PREVIOUS},
    {nullptr,      0x280000000, RAM_SIZE,     MV_MIRROR_PREVIOUS},
    {nullptr,      0x2C0000000, RAM_SIZE,     MV_MIRROR_PREVIOUS},
    {nullptr,  0x2E0000000, L1_CACHE_SIZE, 0},
    {nullptr, 0x27E000000, FAKEVMEM_SIZE, MV_FAKE_VMEM},
    {nullptr,    0x10000000, EXRAM_SIZE,    MV_WII_ONLY},
    {nullptr,      0x290000000, EXRAM_SIZE,   MV_WII_ONLY | MV_MIRROR_PREVIOUS},
    {nullptr,      0x2D0000000, EXRAM_SIZE,   MV_WII_ONLY | MV_MIRROR_PREVIOUS},
};

static const int num_views = sizeof(views) / sizeof(MemoryView);
static MemArena g_arena;

#define SKIP(a_flags, b_flags) \
if (!(a_flags & MV_WII_ONLY) && (b_flags & MV_WII_ONLY)) \
continue; \
if (!(a_flags & MV_FAKE_VMEM) && (b_flags & MV_FAKE_VMEM)) \
continue; \


int main(int argc, char * argv[]) {
    /*@autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }*/
    
    // Redirect log output
    redirectLogOutput();
    
    u32 flags = 0;
    flags |= MV_FAKE_VMEM;
    //MemArena g_arena;
    //&g_arena = new MemArena();
    if (1)
    {
        MemoryMap_Setup(views, num_views, flags, &g_arena);
        return 0;
    }

    
    return 0;
}

void redirectLogOutput()
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"console.log"];
    freopen([logPath fileSystemRepresentation],"a+",stderr);
}

void MemArena::GrabSHMSegment(size_t size)
{
    for (int i = 0; i < 10000; i++)
    {
        std::string file_name = format("dolphinmem.%d", i);
        fd = shm_open(file_name.c_str(), O_RDWR | O_CREAT | O_EXCL, 0600);
        if (fd != -1)
        {
            shm_unlink(file_name.c_str());
            break;
        }
        else if (errno != EEXIST)
        {
            NSLog(@"GrabSHMSegment: shm_open failed: %s", strerror(errno));
            //ERROR_LOG(MEMMAP, "shm_open failed: %s", strerror(errno));
            return;
        }
    }
    if (ftruncate(fd, size) < 0)
        //ERROR_LOG(MEMMAP, "Failed to allocate low memory space");
        NSLog(@"GrabSHMSegment: Failed to allocate low memory space");
}


void MemArena::ReleaseSHMSegment()
{
    close(fd);
}


void *MemArena::CreateView(s64 offset, size_t size, void *base)
{
    //NSLog(@"base: %p | size: %zu | offset: %lli", base, size, offset);
    void *retval = mmap(
                        base, size,
                        PROT_READ | PROT_WRITE,
                        MAP_SHARED | ((base == nullptr) ? 0 : MAP_FIXED),
                        fd, offset);
    
    if (retval == MAP_FAILED)
    {
        NSLog(@"CreateView: mmap failed, %s", strerror(errno));
        return nullptr;
    }
    else
    {
        return retval;
    }
}


void MemArena::ReleaseView(void* view, size_t size)
{
    munmap(view, size);
}


u8* MemArena::FindMemoryBase()
{//0x31000000, 0x400000000
    void* base = mmap(0, 0x31000000, PROT_READ | PROT_WRITE,
                      MAP_ANON | MAP_SHARED, -1, 0);
    if (base == MAP_FAILED) {
        NSLog(@"Failed to map memory space: %s", strerror(errno));
        return 0;
    }
    munmap(base, 0x31000000);
    NSLog(@"FindMemoryBase: base at %p", base);
    return static_cast<u8*>(base);
    //return reinterpret_cast<u8*>(0x2300000000ULL);
}


// yeah, this could also be done in like two bitwise ops...
#define SKIP(a_flags, b_flags) \
if (!(a_flags & MV_WII_ONLY) && (b_flags & MV_WII_ONLY)) \
continue; \
if (!(a_flags & MV_FAKE_VMEM) && (b_flags & MV_FAKE_VMEM)) \
continue; \

static bool Memory_TryBase(u8 *base, MemoryView *views, int num_views, u32 flags, MemArena *arena)
{
    // OK, we know where to find free space. Now grab it!
    // We just mimic the popular BAT setup.
    
    int i;
    for (i = 0; i < num_views; i++)
    {
        MemoryView* view = &views[i];
        void* view_base;
        
        SKIP(flags, view->flags);
        
        // On 64-bit, we map the same file position multiple times, so we
        // don't need the software fallback for the mirrors.
        view_base = base + view->virtual_address;
        void* pointerbase = static_cast<u8*>(base);
        NSLog(@"view base: %p, | vaddress: 0x%llx | base: %p", view_base, view->virtual_address,
              pointerbase);
        NSLog(@"shm: %u | size: %u", view->shm_position, view->size);
        view->mapped_ptr = arena->CreateView(view->shm_position, view->size, view_base);
        view->view_ptr = view->mapped_ptr;
        
        if (!view->view_ptr)
        {
            // Argh! ERROR! Free what we grabbed so far so we can try again.
            NSLog(@"TryBase: error, shutting down");
            MemoryMap_Shutdown(views, i+1, flags, arena);
            return false;
        }
        
        if (view->out_ptr)
            *(view->out_ptr) = (u8*) view->view_ptr;
    }
    NSLog(@"TryBase: we're done here :D");
    return true;
}

static u32 MemoryMap_InitializeViews(MemoryView *views, int num_views, u32 flags)
{
    u32 shm_position = 0;
    u32 last_position = 0;
    
    for (int i = 0; i < num_views; i++)
    {
        NSLog(@"InitializeViews: %i", i);
        // Zero all the pointers to be sure.
        views[i].mapped_ptr = nullptr;
        
        SKIP(flags, views[i].flags);
        
        if (views[i].flags & MV_MIRROR_PREVIOUS)
            shm_position = last_position;
        views[i].shm_position = shm_position;
        last_position = shm_position;
        shm_position += views[i].size;
    }
    
    return shm_position;
}

u8 *MemoryMap_Setup(MemoryView *views, int num_views, u32 flags, MemArena *arena)
{
    u32 total_mem = MemoryMap_InitializeViews(views, num_views, flags);
    
    arena->GrabSHMSegment(total_mem);
    
    // Now, create views in high memory where there's plenty of space.
    u8 *base = MemArena::FindMemoryBase();
    // This really shouldn't fail - in 64-bit, there will always be enough
    // address space.
    if (!Memory_TryBase(base, views, num_views, flags, arena))
    {
        NSLog(@"MemoryMap_Setup: Failed finding a memory base.");
        return nullptr;
    }
    return base;
}

void MemoryMap_Shutdown(MemoryView *views, int num_views, u32 flags, MemArena *arena)
{
    std::set<void*> freeset;
    for (int i = 0; i < num_views; i++)
    {
        MemoryView* view = &views[i];
        if (view->mapped_ptr && !freeset.count(view->mapped_ptr))
        {
            arena->ReleaseView(view->mapped_ptr, view->size);
            freeset.insert(view->mapped_ptr);
            view->mapped_ptr = nullptr;
        }
    }
}

inline std::string format(const char* fmt, ...){
    int size = 512;
    char* buffer = 0;
    buffer = new char[size];
    va_list vl;
    va_start(vl, fmt);
    int nsize = vsnprintf(buffer, size, fmt, vl);
    if(size<=nsize){ //fail delete buffer and try again
        delete[] buffer;
        buffer = 0;
        buffer = new char[nsize+1]; //+1 for /0
        nsize = vsnprintf(buffer, size, fmt, vl);
    }
    std::string ret(buffer);
    va_end(vl);
    delete[] buffer;
    return ret;
}
