import struct, uuid, sys
def align(x,a): return (x+a-1)&~(a-1)
def sections(data):
    off=0; out=[]
    while off+4<=len(data):
        sz=int.from_bytes(data[off:off+3],'little'); typ=data[off+3]; hdr=4
        if sz==0xffffff: sz=struct.unpack_from('<I',data,off+4)[0]; hdr=8
        if sz<hdr: break
        out.append((typ,data[off+hdr:off+sz],data[off:off+sz])); off=align(off+sz,4)
    return out
def ui_name(secs):
    for t,b,_ in secs:
        if t==0x15: return b.decode('utf-16-le').rstrip('\0')
    return None
def fv_files(fv):
    hlen=struct.unpack_from('<H',fv,0x30)[0]; flen=struct.unpack_from('<Q',fv,0x20)[0]
    off=hlen
    # extended header
    ext=struct.unpack_from('<H',fv,0x34)[0]
    if ext: 
        esz=struct.unpack_from('<I',fv,ext+16)[0]; off=align(ext+esz,8)
    while off+24<=min(flen,len(fv)):
        name=uuid.UUID(bytes_le=bytes(fv[off:off+16])); typ=fv[off+18]; attr=fv[off+19]
        sz=int.from_bytes(fv[off+20:off+23],'little'); hdr=24
        if sz==0xffffff and fv[off:off+16]==b'\xff'*16: break
        if attr&1: sz=struct.unpack_from('<Q',fv,off+24)[0]; hdr=32
        if sz<hdr or sz==0xffffff: break
        yield name,typ,fv[off+hdr:off+sz],fv[off:off+sz]
        off=align(off+sz,8)
