# ᛟ minc | Minimalistic C Language
`Min> C <niM`  
MinC is a minimalistic C language with nim syntax.  
It does not try to be feature-full, its only goal is to write Modern and Pure C.  

See the @[What is MinC](./doc/minc.md) doc file for an overview of the lang.  

## Current State of Development
TL;DR: **Early** :)  
::
```text
The language works, and can create full applications.  

The current way to work with the language involves continuously hitting assertions,  
with very little (or at times none) error information, other than the backtrace and a treeRepr of the code that crashed.  

See the todo and done folders for a complete list of features implemented and tbd.  
There is also a roadmap file, used for version planning and goal-setting.  
```

@[done](./doc/done/)  
@[todo](./doc/todo/), @[roadmap](./doc/roadmap.md)  
Full application example @[app03 Framebuffer OpenGL](./examples/app03_framebufferGL)  

### Build requirements
`bash`/`powershell`, git, gcc, libubsan  
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/heysokam/minc/master/src/build/clone.ps1)

# Optional: Add `~/.minc/bin` and `~/.cmin/bin` to your PATH variable
# For Bash Shell: Add this to your `~/.bashrc`
[[ -d "$HOME/.minc/bin" ]] && export PATH="$PATH:$HOME/.minc/bin"
[[ -d "$HOME/.minc/bin/.nim/bin" ]] && export PATH="$PATH:$HOME/.minc/bin/.nim/bin"
```

```md
# TODO !!# Platform specific quirks
Some Linux systems don't have a global libubsan link stored in any of the folders that ZigCC searches for it.
Will need to create a symbolic link for libubsan to be able to compile applications in debug mode.
# Gentoo
`ln -s /usr/lib/gcc/x86_64-pc-linux-gnu/13/libubsan.so /usr/local/lib64/libubsan.so`
Change the `../13/..` to whatever version of gcc your system is using.
# Ubuntu
`sudo ln -s /usr/lib/gcc/x86_64-linux-gnu/12/libubsan.so /usr/lib64/libubsan.so`
Change the `../12/..` to whatever version of gcc your system is using.
```

## Compiler
MinC uses an StoS compiler that generates C code.  
The generated output code is standard, human-readable and editable C code.  
The output code is then compiled with a regular C compiler as usual.  

MinC can be used to create C libraries, because the output is normal C code.  

Cross-compilation is a first class citizen.  
Thanks to the internal usage of the ZigCC compiler interface,  
building for any target is as easy as passing -target= to the compiler command.  

## *Slate | Compiler Helper Library
Code generation relies on its companion library @[*Slate](https://github.com/heysokam/slate),  
which is also in early stages of development.  
Over time, many of its internal features will be removed from the compiler and moved to *Slate instead,  
in order to make them usable for compilation of Nim into other languages.  
