# BLAKE3 against the project's own published test vectors (blake3_gen.py prints
# this file). The first 35 rows are test_vectors.json entire -- the same input,
# the bytes i % 251, and the same 64 hex digits the b3sum command prints. The
# rest pin the pieces: a range that is not the whole buffer, a leaf at a chunk
# counter, and a root built by hand out of two and four leaves, which is the
# law a forked hash needs and the only reason blake3_par can fork at all.
import Base
import ../../power/vec.bend as Vec
import ../../power/bytes.bend as Bytes
import ../../power/blake3.bend as B3

# the official input: the bytes i % 251, repeating
def fill(fuel: Nat, +i: U32, b: Bytes()) -> Bytes():
  match fuel:
    case 0n:
      b
    case 1n++p:
      fill(p, U32.inc(i), Bytes.push(b, U32.mod(i, 251)))

def buf(n: Nat) -> Bytes():
  fill(n, 0, Bytes.new())

def out(r: Bytes() & B3.Cv) -> String:
  (b, c) = r
  B3.hex(c)

def one(n: Nat) -> String:
  out(B3.hash_all(buf(n)))

def at(tot: Nat, +off: U32, +n: U32) -> String:
  out(B3.hash(buf(tot), off, n))

def leaf(+n: Nat, t: U32) -> String:
  out(B3.chunk(buf(n), 0, U32.from_nat(n), t, 0))

# two leaves, joined: chunk 0 is the first 1,024 bytes, chunk 1 the rest, and
# the root is their parent with ROOT set
def two.join(c0: B3.Cv, r: Bytes() & B3.Cv) -> String:
  (b, c1) = r
  B3.hex(B3.parent(c0, c1, 8))

def two.right(+nr: U32, r: Bytes() & B3.Cv) -> String:
  (b, c0) = r
  two.join(c0, B3.chunk(b, 1024, nr, 1, 0))

def two(n: Nat, +nr: U32) -> String:
  two.right(nr, B3.chunk(buf(n), 0, 1024, 0, 0))

# four leaves: the same law one level deeper, which is the shape a fork tree of
# any depth is made of
def four.d(c0: B3.Cv, c1: B3.Cv, c2: B3.Cv, r: Bytes() & B3.Cv) -> String:
  (b, c3) = r
  B3.hex(B3.parent(B3.parent(c0, c1, 0), B3.parent(c2, c3, 0), 8))

def four.c(c0: B3.Cv, c1: B3.Cv, r: Bytes() & B3.Cv) -> String:
  (b, c2) = r
  four.d(c0, c1, c2, B3.chunk(b, 3072, 1024, 3, 0))

def four.b(c0: B3.Cv, r: Bytes() & B3.Cv) -> String:
  (b, c1) = r
  four.c(c0, c1, B3.chunk(b, 2048, 1024, 2, 0))

def four.a(r: Bytes() & B3.Cv) -> String:
  (b, c0) = r
  four.b(c0, B3.chunk(b, 1024, 1024, 1, 0))

def four() -> String:
  four.a(B3.chunk(buf(4096n), 0, 1024, 0, 0))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(one(0n))
    IO.print(one(1n))
    IO.print(one(2n))
    IO.print(one(3n))
    IO.print(one(4n))
    IO.print(one(5n))
    IO.print(one(6n))
    IO.print(one(7n))
    IO.print(one(8n))
    IO.print(one(63n))
    IO.print(one(64n))
    IO.print(one(65n))
    IO.print(one(127n))
    IO.print(one(128n))
    IO.print(one(129n))
    IO.print(one(1023n))
    IO.print(one(1024n))
    IO.print(one(1025n))
    IO.print(one(2048n))
    IO.print(one(2049n))
    IO.print(one(3072n))
    IO.print(one(3073n))
    IO.print(one(4096n))
    IO.print(one(4097n))
    IO.print(one(5120n))
    IO.print(one(5121n))
    IO.print(one(6144n))
    IO.print(one(6145n))
    IO.print(one(7168n))
    IO.print(one(7169n))
    IO.print(one(8192n))
    IO.print(one(8193n))
    IO.print(one(16384n))
    IO.print(one(31744n))
    IO.print(one(102400n))
    IO.print(at(64n, 0, 0))
    IO.print(at(64n, 7, 0))
    IO.print(at(64n, 1, 63))
    IO.print(at(64n, 8, 8))
    IO.print(at(64n, 32, 32))
    IO.print(at(300n, 1, 255))
    IO.print(at(300n, 44, 256))
    IO.print(at(300n, 0, 300))
    IO.print(at(300n, 299, 1))
    IO.print(at(3000n, 100, 1024))
    IO.print(at(3000n, 1000, 2000))
    IO.print(at(3000n, 5, 2048))
    IO.print(leaf(0n, 0))
    IO.print(leaf(1n, 0))
    IO.print(leaf(64n, 0))
    IO.print(leaf(1024n, 0))
    IO.print(leaf(1024n, 1))
    IO.print(leaf(1024n, 7))
    IO.print(leaf(1024n, 1000))
    IO.print(leaf(700n, 3))
    IO.print(leaf(65n, 9))
    IO.print(two(1025n, 1))
    IO.print(two(1500n, 476))
    IO.print(two(2048n, 1024))
    IO.print(four())
#|af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262
#|2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213
#|7b7015bb92cf0b318037702a6cdd81dee41224f734684c2c122cd6359cb1ee63
#|e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f
#|f30f5ab28fe047904037f77b6da4fea1e27241c5d132638d8bedce9d40494f32
#|b40b44dfd97e7a84a996a91af8b85188c66c126940ba7aad2e7ae6b385402aa2
#|06c4e8ffb6872fad96f9aaca5eee1553eb62aed0ad7198cef42e87f6a616c844
#|3f8770f387faad08faa9d8414e9f449ac68e6ff0417f673f602a646a891419fe
#|2351207d04fc16ade43ccab08600939c7c1fa70a5c0aaca76063d04c3228eaeb
#|e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b
#|4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98
#|de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee
#|d81293fda863f008c09e92fc382a81f5a0b4a1251cba1634016a0f86a6bd640d
#|f17e570564b26578c33bb7f44643f539624b05df1a76c81f30acd548c44b45ef
#|683aaae9f3c5ba37eaaf072aed0f9e30bac0865137bae68b1fde4ca2aebdcb12
#|10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11
#|42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7
#|d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444
#|e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a
#|5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030
#|b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2
#|7124b49501012f81cc7f11ca069ec9226cecb8a2c850cfe644e327d22d3e1cd3
#|015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969
#|9b4052b38f1c5fc8b1f9ff7ac7b27cd242487b3d890d15c96a1c25b8aa0fb995
#|9cadc15fed8b5d854562b26a9536d9707cadeda9b143978f319ab34230535833
#|628bd2cb2004694adaab7bbd778a25df25c47b9d4155a55f8fbd79f2fe154cff
#|3e2e5b74e048f3add6d21faab3f83aa44d3b2278afb83b80b3c35164ebeca205
#|f1323a8631446cc50536a9f705ee5cb619424d46887f3c376c695b70e0f0507f
#|61da957ec2499a95d6b8023e2b0e604ec7f6b50e80a9678b89d2628e99ada77a
#|a003fc7a51754a9b3c7fae0367ab3d782dccf28855a03d435f8cfe74605e7817
#|aae792484c8efe4f19e2ca7d371d8c467ffb10748d8a5a1ae579948f718a2a63
#|bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b
#|f875d6646de28985646f34ee13be9a576fd515f76b5b0a26bb324735041ddde4
#|62b6960e1a44bcc1eb1a611a8d6235b6b4b78f32e7abc4fb4c6cdcce94895c47
#|bc3e3d41a1146b069abffad3c0d44860cf664390afce4d9661f7902e7943e085
#|af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262
#|af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262
#|e1618a77834186c74138c5c00a01989f2005dad18b78f1216816722dce965a0b
#|78534dd0ab885fda45e90541b73c2dd13e919598b6c18b4232ebf7696a945fa2
#|ae2e33e7454f93fc60c3553de5a05953260e7fdbc0120ae286bb6bb2b347052a
#|2810d3671399d879bb8d4ecf5ff94ee4e2b989eb5d856d0ec23f886cbd0cc07c
#|42765840204a01b827de68f2e3aa09ae8e256d693feec4ea0042cf46280e5fe9
#|1309d44c9edaf51147844a5f38f884225acb365d7a5b4de34ef328671b5c6af5
#|4d067153ac729a4a7e8220c97935ffba67487860d58298ceeb23864369867d9f
#|ffd7110aa7b42bbdce793797a50f5796e50fa04ad358b14e057672715ab8dcb3
#|26baabd33c86b21394bb5b529a0c2400e69979a92068cfbc1665f962bae8ffde
#|435206dc271c1a64b4b699cbd1ca284b8e7458020ac543ed6c1d0c67a811049c
#|b4686b3c8d953f4d185d51bc9cd7bce6d9782d7659f8c06068d4c3ffa6e56841
#|0df1a7881d71d287d0afc2fcd7d23d28f12e401ab858ca267f11c5f1710df315
#|6dde41c9d05a39b09b486620f2c3cf7652fde7f3eb412353d95734294c5d348e
#|5c9e654411e393d1f4bec710ccd5bc5669ab177d610a0eb691fcfee92fb4e8b1
#|2726742c4fe49c461d4b570f9643cc7ac6c52251d457c9b3303c10cd9c6d258b
#|ef7dc988dd01c728276007b99f01b83dbd21f374d7e90df60deba977097390d1
#|a0fff949abbaf50d52724e3a0d434547c35c5b069b478369d7bf88fa659cbdb9
#|518148b30e4415d619b679bece116b4824ac66d77ffd4fb2edbfd044314cf32f
#|b9d437fc3b7985ac98cb627251b48863a3e75b14e060ca1e2d9bdda3356987cb
#|d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444
#|e71e67e776854018461734062301034d08f1be79d8fa59ae1daf61eda2c65318
#|e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a
#|015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969
