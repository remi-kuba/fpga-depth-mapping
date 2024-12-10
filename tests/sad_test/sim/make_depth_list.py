def depths(offset):
    res = []
    for i in range(offset+1):
        res.append(int((i / offset) * 255))
    return res

def main():
    offset = 30
    depth = depths(offset)
    print(depth)

main()