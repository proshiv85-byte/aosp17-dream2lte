// Write an Android sparse image, read from stdin, to a block device.
//
// Used by the TWRP installer: unzip -p "$ZIP" system.img | sparse_write /dev/block/...
// "Don't care" chunks are zeroed (BLKZEROOUT, falling back to writing
// zeros), so the whole partition ends up byte-identical to the raw image and
// can be verified with sha256sum.
//
// Build: aarch64-linux-gnu-gcc -static -O2 -o sparse_write sparse_write.c

#include <errno.h>
#include <fcntl.h>
#include <linux/fs.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define SPARSE_MAGIC 0xed26ff3a
#define CHUNK_RAW 0xcac1
#define CHUNK_FILL 0xcac2
#define CHUNK_DONT_CARE 0xcac3
#define CHUNK_CRC32 0xcac4

struct sparse_header {
    uint32_t magic;
    uint16_t major_version, minor_version;
    uint16_t file_hdr_sz, chunk_hdr_sz;
    uint32_t blk_sz, total_blks, total_chunks, image_checksum;
};

struct chunk_header {
    uint16_t chunk_type, reserved1;
    uint32_t chunk_sz, total_sz;
};

static char buf[4 << 20];

static void die(const char* msg) {
    fprintf(stderr, "sparse_write: %s (%s)\n", msg, strerror(errno));
    exit(1);
}

static void read_full(void* p, size_t n) {
    char* c = p;
    while (n) {
        ssize_t r = read(0, c, n);
        if (r == 0) { errno = 0; die("unexpected end of image"); }
        if (r < 0) { if (errno == EINTR) continue; die("read failed"); }
        c += r;
        n -= r;
    }
}

static void skip(size_t n) {
    while (n) {
        size_t k = n < sizeof(buf) ? n : sizeof(buf);
        read_full(buf, k);
        n -= k;
    }
}

static void write_full(int fd, const void* p, size_t n, off_t off) {
    const char* c = p;
    while (n) {
        ssize_t w = pwrite(fd, c, n, off);
        if (w < 0) { if (errno == EINTR) continue; die("write failed"); }
        c += w;
        n -= w;
        off += w;
    }
}

static void zero_range(int fd, off_t off, uint64_t len) {
    uint64_t range[2] = {off, len};
    if (ioctl(fd, BLKZEROOUT, range) == 0) return;
    memset(buf, 0, sizeof(buf));
    while (len) {
        size_t k = len < sizeof(buf) ? len : sizeof(buf);
        write_full(fd, buf, k, off);
        off += k;
        len -= k;
    }
}

int main(int argc, char** argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <block device> < image\n", argv[0]);
        return 2;
    }
    int fd = open(argv[1], O_WRONLY);
    if (fd < 0) die("cannot open output");

    struct sparse_header h;
    read_full(&h, sizeof(h));
    if (h.magic != SPARSE_MAGIC || h.major_version != 1 || h.blk_sz % 4096 ||
        h.file_hdr_sz < sizeof(h) || h.chunk_hdr_sz < sizeof(struct chunk_header)) {
        errno = 0;
        die("not a supported Android sparse image");
    }
    skip(h.file_hdr_sz - sizeof(h));

    uint64_t dev_size = 0, img_size = (uint64_t)h.total_blks * h.blk_sz;
    if (ioctl(fd, BLKGETSIZE64, &dev_size) == 0 && dev_size < img_size) {
        errno = 0;
        die("image is larger than the partition");
    }

    off_t off = 0;
    for (uint32_t i = 0; i < h.total_chunks; i++) {
        struct chunk_header c;
        read_full(&c, sizeof(c));
        skip(h.chunk_hdr_sz - sizeof(c));
        uint64_t len = (uint64_t)c.chunk_sz * h.blk_sz;
        uint32_t data = c.total_sz - h.chunk_hdr_sz;
        switch (c.chunk_type) {
            case CHUNK_RAW:
                if (data != len) { errno = 0; die("bad raw chunk"); }
                for (uint64_t done = 0; done < len;) {
                    size_t k = len - done < sizeof(buf) ? len - done : sizeof(buf);
                    read_full(buf, k);
                    write_full(fd, buf, k, off + done);
                    done += k;
                }
                break;
            case CHUNK_FILL: {
                uint32_t v;
                if (data != 4) { errno = 0; die("bad fill chunk"); }
                read_full(&v, 4);
                if (v == 0) { zero_range(fd, off, len); break; }
                for (size_t j = 0; j < sizeof(buf) / 4; j++) ((uint32_t*)buf)[j] = v;
                for (uint64_t done = 0; done < len;) {
                    size_t k = len - done < sizeof(buf) ? len - done : sizeof(buf);
                    write_full(fd, buf, k, off + done);
                    done += k;
                }
                break;
            }
            case CHUNK_DONT_CARE:
                zero_range(fd, off, len);
                break;
            case CHUNK_CRC32:
                skip(data);
                break;
            default:
                errno = 0;
                die("unknown chunk type");
        }
        if (c.chunk_type != CHUNK_CRC32) off += len;
        fprintf(stderr, "\r%u/%u chunks", i + 1, h.total_chunks);
    }
    fprintf(stderr, "\n");
    if ((uint64_t)off != img_size) { errno = 0; die("image size mismatch"); }
    if (fsync(fd) != 0) die("fsync failed");
    return close(fd) == 0 ? 0 : 1;
}
