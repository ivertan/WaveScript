


/* 
   This file uses the foreign interface to provide access to some file
   IO, shell access, and unix system calls.  A comprehensive job would
   be very involved, so we're adding to this as need arrises (as with
   all our libraries, really).
  
  .author Ryan Newton
  
 */

/******************************************************************************/
/*    This namespace contains things that are direct wrappers to Unix calls   */

type FileDescr = Pointer "FILE*";

namespace Unix {

  namespace Internal {
    ext = "dylib" // or .so
    //libc = ["libc."++ext]
    //libc = ["./libc.so"]
    libc = []
  }

  //using Internal;

  stdio = "stdio.h":::Internal:libc;

  // Can we support error codes across backends?
  system :: String -> Int = 
     foreign("system", "stdlib.h":::Internal:libc)

  usleep :: Int -> () = 
     foreign("usleep","unistd.h":::Internal:libc)

  fopen  :: (String, String) -> FileDescr = foreign("fopen",  stdio);
  fclose :: FileDescr -> Int              = foreign("fclose", stdio);
  
  fgets  :: (String, Int, FileDescr) -> Pointer "char*" = foreign("fgets",  stdio);

  fflush :: FileDescr -> () = foreign("fflush",  stdio);

  // Only supporting foreign *functions* right now.
  //stdout :: FileDescr = foreign("stdout",  stdio);

  puts :: String -> () = foreign("puts", stdio);

  // This is kind of funny, we have multiple interfaces into the same functions.
  // One set reads from an *external* pointer:
  fread :: (Pointer "void*", Int, Int, FileDescr) -> Int = 
     foreign("fread", stdio)
  fwrite :: (Pointer "void*", Int, Int, FileDescr) -> Int = 
     foreign("fwrite", stdio)

  // The second interface reads from WS arrays:
  // Damn, strings are not mutable...
  fread_arr :: (Array Char, Int, Int, FileDescr) -> Int = 
    foreign("fread", stdio)
  fwrite_arr :: (Array Char, Int, Int, FileDescr) -> Int = 
    foreign("fwrite", stdio)

  // The third interface reads from WS strings:
  fread_str :: (String, Int, Int, FileDescr) -> Int = 
    foreign("fread", stdio)
  fwrite_str :: (String, Int, Int, FileDescr) -> Int = 
    foreign("fwrite", stdio)

  malloc :: Int -> Pointer "void*" = foreign("malloc",[]);

} // End namespace




/******************************************************************************/
/* The rest of this file contains functionality built on top of the
   basic unix calls. */






/* // Write a stream of strings to disk.  Returns an empty stream */
/* fileSink :: (String, String, Stream String)  -> Stream nothing; */
/* fun fileSink (filename, mode, strm) { */
/*   iterate str in strm {   */
/*     state { */
/*       fp = Unix:fopen(filename, mode) */
/*     } */
/*     // This is very inefficient, it should be fixed: */
/*     arr = List:toArray( String:explode(str)); */
/*     len = Array:length(arr); */
/*     cnt = Unix:fwrite_arr(arr, 1, len, fp); */
/*     if cnt != len  */
/*     then wserror("fileSink: fwrite failed to write data") */
/*   } */
/* } */



// Write a stream of strings to disk.  Returns a stream of ACKS (units)
// Mode string should be valid input to fopen.
fileSink :: (String, String, Stream String)  -> Stream nothing;
fun fileSink (filename, mode, strm) {
  iterate str in strm {  
    state { 
      fst = true;
      fp = ptrMakeNull();
    }
    if fst then {
      fp := Unix:fopen(filename, mode);
      fst = false;
    };
    // This is very inefficient, it should be fixed:
    //arr = List:toArray( String:explode(str));
    //len = Array:length(arr);
    ////arr2 = Array:map(fun(c) Uint8! charToInt(c), arr);
    //cnt = Unix:fwrite_arr(arr, 1, len, fp);
    
    len = String:length(str);
    cnt = Unix:fwrite_str(str, 1, len, fp);

    // This is inefficient, but we flush on every write.
    Unix:fflush(fp);
    emit ();

    if cnt != len 
    then wserror("fileSink: fwrite failed to write data")
  }
}



  c_exts = ["unix_wrappers.c"];  // C extensions that go with this file.
  scandir_sorted :: (String, Pointer "struct dirent ***") -> Int = foreign("scandir_sorted", c_exts);
  ws_namelist_ptr :: () -> Pointer "struct dirent ***" = foreign("ws_namelist_ptr", c_exts);
  getname :: (Pointer "struct dirent ***", Int) -> String = foreign("getname", c_exts);
  freenamelist :: (Pointer "struct dirent ***", Int) -> () = foreign("freenamelist", c_exts);



// The WaveScript version of scandir reads all the names into a WS array of WS strings.
// It will throw a wserror if it cannot read the directory.  It sorts alphabetically.
scandir :: String -> Array String;
fun scandir(dir) {
  files = ws_namelist_ptr();
  count = scandir_sorted(dir, files);
  // This ASSUMES that . and .. will be in the list, and will be sorted first.
  names = Array:build(count-2, fun(ind) {
     getname(files, ind+2);
   });
  freenamelist(files, count);
  // This is inefficient, we filter the array to remove "." and ".."
  //Array:filter(fun(s) { s != "." && s != ".." }, names)
  names
}

// Scan a directory for files and stream the file names.
// This version sorts alphabetically:
fun scandir_stream(dir, ticks) {
  iterate _ in ticks {
    state { count = -1; 
            index = 0;
            files = ptrMakeNull(); 
          }
    // Initialize:
    if count == -1 then {
      files := ws_namelist_ptr();
      count := scandir_sorted(dir, files);
    };
    if index == count then {
      freenamelist(files, count);
    };
    if index < count then {
      name = getname(files, index);
      index += 1;
      // We prune out "." and "..".
      if not(name == "." || name == "..")
      then emit name;
    }
  }
}


// Scan a directory but give random access to the filenames based on index (alphabetically)
// When an index is out of bounds do nothing.
// UNFINISHED:
//fun scandir_random_access_stream(dir, indices) {
/*
fun scandir_stream(dir, indices) {
  iterate ind in ticks {
    state { total = -1; 
            index = 0;
            files = ptrMakeNull(); 
          }
    // Initialize:
    if total == -1 then {
      files := ws_namelist_ptr(); // namelist is never freed
      total := scandir_sorted(dir, files);
    };

    if index < total then {
      name = getname(files, index);
      index += 1;
      // We prune out "." and "..".
      if not(name == "." || name == "..")
      then emit name;
    }
  }
}
*/



// A simple test:
main = { 
  strings = iterate _ in timer(3.0) {
    state { cnt = 0; 
            stdout = Unix:fopen("/dev/stdout", "a");
          }
    using Unix;
    s = "Emitting "++cnt++"\n";
    //print("Trying to print through stdout... string length "++String:length(s)++"\n");
    fwrite_str(s, 1, String:length(s), stdout);
    fflush(stdout);
    if cnt < 15 then emit cnt++"\n";
    cnt += 1;  
  };
  fileSink("stream.out", "a", strings);
  //strings
}



/*

BASE <- iterate _ in timer$ 3.0 {
  state {fst=true}
  
  using Unix;

  if fst then {
    print$ "woot\n";

    // WEIRD!!!! USLEEP WORKS IN ONE PLACE BUT NOT THE OTHER.
    //    usleep(1000000);
    system("ls");
    usleep(500000);
    print$ "yay finished!\n";

    fp = fopen("foo.out","w");
    
    print("Got file handle ! "++fp++"\n");

    buf = List:toArray$ String:explode$ "foobar\nbaz";

    print$ "Allocated buffer to send...\n";

    cnt = fwrite_arr(buf, 1,7, fp);

    print$ "Wrote "++cnt++" characters to file!\n";

    inbuf = malloc(10);
    fclose(fp);
    fp2 = fopen("foo.out","r");

    cnt2 = fread(inbuf, 1,7, fp2);
    str = String:implode$ Array:toList$ (ptrToArray(inbuf,7) :: Array Char);
    
    print$ "Read back "++cnt2++" chars: <"++str++">\n";
    
    emit 1;
  };
  fst := false;
  emit 0;
}


*/
