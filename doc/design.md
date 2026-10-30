// Comment

//! Top level doc comment 
/// importing other files or
/// modules just moves them into 
/// nameless structs, files can be imported via
/// Absolute path from project or relative path from 
/// File importing it
/// Modules are folders with foldername.mtl file 
/// inside or depencencies  and are imported like
const math1 = @import("math")
/// or ewuvalent
const math2 = @import("math/math.mtl")  
/// or for installeddependecies
const math3 = @import("pkg:math")
/// or for std lib
const math4 = @import("std:math")
/// Doc comment for function or code in it
/// pub makes identifiers (such as functions, types /// and global varables and constants) visible to   /// outside
/// def followed by function name parethesis and /// return type defines a function 
/// void - a type of size 0
pub def main() void { 
    /// variable of type unsigned int32 
    /// semicolon not needed
    var num1: u32 = 21
    /// constant of type comptime_int
    /// type may be ommited for consts
    /// No name shadowing allowed
    /// semicolon may optionally be 
    const num2 = 12;
    // num2 += 1 // error cannot mutate a constant 
   /// Numbers literals have 4 forms
   /// Normal (decimal)
    const num3 = 1000000;
   /// Underscore one (all forms)
    const num4 = 1_000_000;
    /// Scientific (decimal only), e may be E, also allows 1.5e-9 
    const num5 = 1e9 // or 1E9
    /// Binary, b may be B
   const num6 = 0b1010 // 10
    /// Octal, o may be O
     const num7 = 0o12; // 10
   /// Hexadecimal, x may be X
   const num8 = 0x0A // 10
    /// Complex (decimal), allows both i or j
   /// Is by default a float 
    const num9 = 10 + 12i
     const num10 = 10 + 12j
  /// Another builtin number type is a arbitrary     
  /// precison numbers iN uN fN cN, which can hold    /// a number of arbitrary length 
  var num11: iN = 1e9999
/// If needed isize and usize are types which have 
/// their size equal to the ptr size on the 
///architecture  so on 32bit systems it has 32 bits ///and on 64bit has 64
   /// nullable values are indicated by prefix ?
   /// errors cannot be null
   var opt_num: ?u32 = null 
   /// Types have format errorunion!?u32 where 
  /// Errorunion! And ? Are optional
    /// type alias
    const uint = u32
    /// Primitive number types
    /// ints:       i8 i16 i32 i64 i128 iN
    /// uints:     u8 u16 u32 i64 u128 uN
    /// floats:    f16 f32 f64 f80 f128 fN
   /// complex: c16 c32 c64 c80 c128 cN
/comptime_int,comptime_float,comptime_complex
/// usize, isize
    /// array (constant lenght) of i32
   /// trailing comma allowed (and for all literals)
    var arr1: (4)i32 = (1, 2, 3, 4)
    arr[1] += 1  // Allowed
    /// size may be infered
    var arr2: (_)i32 = (5, 6, 7, 8, 9)
    /// constant arrays are tuples
    const arr3 = (1, 2, 3)
     /// Array unpacking
     var y = 4
     var x, y, const z = arr3  // x = 1, y = 2, z = 3
    /// arrays support non homogeneous types
    const arr4 = (arr3, 12.3, num1)
    /// With explicit types
  const arr4: ((5)i32, i32, u32) = (arr2, arr1[2], num1)
    /// dynamic list of variable length of i32
    var list: []i32 = [1, 2, 3, 4]
/// There a re also list of anys *any or &any
/// Any requires a type.assert before use if the 
/// Compiler cannot guarantee its type
/// String literals if cannot have infered will be
///  constlen
var lista: []&any = [1, 1.2, 1i, "hi"]
    /// u8 based string of constant length 
    var str1: (_)u8str = "string1"
    /// u8 based string of varaible length 
    var str2: []u8str = "A string"
    /// multi line string 
    var str2: []u8str = """
                                  I am multi line!!!
                                  """
    /// dictionary of u32 to i32
    var dict: {u32, i32} = {1: 2, 2: 5} 
    /// set of f64, basically a dict of f64 to void
    var set: {}f64 = {2.0, 2.3, 4.5, 1.1} 
    /// Structs can be created in many ways
    /// using creation syntax
    var struct1: Num = .{ .num = 32 }
    /// using default values
    var struct2: Num = .default
    /// initialization functions 
    var struct3: Num = .init()
    /// constant structs cannot be muted, even by          /// method.calls
    const struct4 = Num{ .num = 32 }
    // struct4.add(4) // Error cannot mutate constant
    /// Variable Reference to struct1
    /// Can mutate the struct or be reasigned    
    /// reference to  a different struct
     var s1: &Num = ^struct1
     /// Constant reference to struct2
     /// Still can mutate the struct, but cannot be        
     //// reasigned
     const s2 = ^struct3
     /// Variable and constant Refrences to other              /// constants cant mutate the original
     var s4_v: &const Num = ^struct4
     const s4_c = ^struct4
     /// Pointers behave in the exact same way, 
     /// variables can be reasigned and constats              /// cannot
     var p1: *Num = &struct1
     const p2 = &struct2
     /// And pointers to comstas are *const and               /// cannot mutete the original 
     var p4_v: *const Num = &struct4
     const p4_c = &struct4
     /// Pointer dereference
     p4_c.*.num
   /// Additionally refrences will have other 
///guarantees such as always pointing to the 
///identifier even, though may disalow identifier 
/// reallocation
    /// Variables can have their types infered using := 
     /// syntax instead of =, but then struct literal 
    /// syntax doesn't work
     var infr := 100
     /// Types can be cast as followed
     var n1: u16 = 10
     var n2: u32 = 10
     /// Safe casts (where data isn't lost)
    var c1: u32 = n1 as u32
     /// Unsafe casts (where data is lost, either by
     /// Downcast or cast to float which cannot hold
    /// The number precisely (eg f32 can hold bigger    /// values than u32, but it cannot hold all u32 vals)
    /// vu32 == @as(@as(vu32, f32), u32) // false for 
    /// some vu32 values. Panicks for downcast, but     /// does not for same size casts to floats
    var c2: @as(n2, u16)
   /// This will ensure the cast is safe
   var c2: @as(n2 % u16.MAX, u16)
/// Slices exist in the language to ensure efficient 
/// And ergonomic Memory views
/// slice of arr1, allows mutating arr1 and reassign 
/// to different slics
var s1: &[u32] = arr1[0..=3] 
/// slice of arr3, constant like references and ptrs
var s3_v1: &[comptime_int]const = arr3[0..=2]
/// You can cast comptime int safely, but it is better 
/// to leave it as it will help with optimization 
var s3_v2: &[i32]const = arr3[0..=2]
/// And you can also make it const 
const s3_v2 = arr3[0..=2]
/// Additionally slices of non homogeneous arrays 
///do not work, unless they are defined like (_)&any 
/// or (_)*any
/// Slices of lists can also be taken
/// But problems arise when the lenght of the lists /// are mutaed as this may cousw reallocation
/// Thats why there are 3 types of slices that exist
/// [T] - type infered by the complier, used in 
///function arguments or return arguments if want /// the caller to decide the type
/// &[T] - refrence type, dissalows for mutateing the 
///lenght of the memory from whcih the virw was ///taken
/// *[T] - a ptr slice type, it allows length mutation
/// And burdens the user to provide code that works
/// Additionally when a slice is taken to a const by 
/// defult it is a ref slics
/// Drop is a keyword that eagerly destroys the ///identifier it refers to and removes it from scope
/// This allows for semj name shadowing, if the
/// item has refrences or pointers then drop (only /// drops from scope
drop list
/// Defer and errdefer like in zig
/// Union usage (constructs the same as struct, but
/// Without default values and named construtrs)
const u1 = MyUnion{ .a = 11} 
// u1.b // Error a fiedl axtive in union
/// Tagged umion
    const u2 = MyTaggedUnion{ .a = 42 };
   /// Sorxh on tagged union
    switch (c) {
        .a => num1 += 1,
        .b => unreachable,
    }
}

/// struct declaration 
const Num = struct {
      /// fields, always public 
      num: f32,
      /// default values are just public constant
      /// members of the struct 
      pub const default = Num{ .num = 0 }
      /// variables in structs are type shared ???
      var amount = 0
      /// Constructors are just public functions 
      pub def init(num: f32) Num {
              return .{ .num = num + 1 }
     }
      /// methods take a reference to the struct type
     /// as their first parameter
      pub def add(self: &Num, num: f32) {
          self.num += num
      }
      /// unless they are static
      pub def get1() void {
          return 1
       }
}


/// Full function definicion
/// pub makes the function visible to imorters
/// inline tell to replece the invocation of the 
/// function with the function body diretly (no call)
/// def followed by function name defines a functio
/// The name is followed by parenthesis with 
/// function arguments
/// The arfuments are of the form name: type 
/// Followed by a comma if there are more of them
/// They allow trailing comma
/// It is possible to make varadic arguments ???
/// Return type is at the end of 
/// Calling function works by writing its name 
/// followed by parenthesis i  which there are
/// arguments, it is also possible to use kwargs
pub inline def dadd(x: u32, y: u32, z..) math.error.Div0!?u32 {
       const a = helper(.a = x, .b = y)
       const b = helper(x, y)
}

def helper(a: u32, b: u32) u32 {
       return x + y
}

/// Unions, define have fileds of different types 
/// Only ine field can be active at a time
const MyUnion1 = union {
    a: i32,
    b: f64,
    c: bool
}
/// Tagged union 
///Unions can be declared with an enum tag type. 
///Ommiting it and writing enum will infer the tag
///This turns the union into a tagged union, which ///makes it eligible to use with switch expressions. ///Tagged unions coerce to their tag type
const MyTaggedUnion = union(enum) {
    a: u8,
    b: void,
};
/// Enums like in zig
/// Errors like in zig

def syntaxshower() {
       var cond: bool = 1 == 3
       if cond {
           
       } else i lf {}
      else
     while cond {}
      for var i: int in 0..10 {}
      for var; i int in arr
      Switch
      
     
}




Todo
Basic syntax(if for etc..., simple for each, range)
Special syntax for nulls
Secial syntax for errors
Lambdas
Function pointers
inline, const and other modifiers and hints such as branch hints and Funciton signature hints etc.

generics (maybe comptime)
Alocator overrides 
Decorators
interfaces
inharitance
magic methods (overlodes etc)

Got mentioned in code but needs to be in details operator precendese table so &arr[1] is the same as &(arr[1]) etc..
Builtins such as @panic
Type introspection @type(), @fields, @size
Some auto dereferencing so i have a ptr to struct s1 which has a field that is a ptr to struct s2 a d has a fuxntion f i would be able to just s1.s2.f() and also s1.*.s2.*.f() i think would be fine, it woulbd be only for struct field or fucntion access
Stuff form (langage consturcts) https://ziglang.org/documentation/master/ 
Solid and robust std
Testing support 
async
Curring
Simd
Exposed functions to see the generated byte code or smt, and byte code hooks to modify it
ABI for dependencies (c and zig extensions possible like in python, but in more ways for interpreted and compiled and byte code at once)



Tooling:
Dependecy management  (install etc + interaction with compiling and compiled dpeendecies)
Way to config per project basis
.mtl folder with
cache folder
cmp-config.json
lsp-config.json
fmt-config.json
pkg-config.json



Info:
The language goal is to be able to be interpreted but also compiled to machine code and also to be compiled to byte code and optimized on byte code (meaby could be done by translating to llvm ir giving llvm to optimize and getting back optimized llvm it (if possible) and then turning it to byte code) and be able to run from byte code and be jit compiled and also after compiled so i can destrobute it as byte code (like .jar) and then before running compile it to native or decide to run it and jit and wasm
Array List Dict Set StrU8 Will be in std.builtins to inherit from and its current types are syntax sugar on top of std.builtins and future genericsgenerics
