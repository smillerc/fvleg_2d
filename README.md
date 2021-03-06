# CATO

## Build/Install
Requirements:
- CMake (3.8+)
- gfortran 8+ or Intel Fortran 2018+
- (TBD) OpenCoarrays ([https://github.com/sourceryinstitute/OpenCoarrays](https://github.com/sourceryinstitute/OpenCoarrays))
- HDF5 using the interface provided by [https://github.com/scivision/h5fortran](https://github.com/scivision/h5fortran)
- pFUnit (for unit testing) ([https://github.com/Goddard-Fortran-Ecosystem/pFUnit](https://github.com/Goddard-Fortran-Ecosystem/pFUnit))

Sample install script
```bash
mkdir build && cd build
CC=gcc FC=gfortran cmake .. -DCMAKE_BUILD_TYPE="Release"
make -j
```

## Examples
Check out the `tests/integrated` folder for a series of different test problems. Note, not all of them are fully functioning, but the majority are.

## Physics
This code solves the Euler fluid equations using a few differente methods. Some of the papers that describe this are listed [here](./papers/Readme.md)

### Influences and Sources of Inspiration

- Scientific Software Design - The Object-Oriented Way ([DOI: https://doi.org/10.1017/CBO9780511977381](https://doi.org/10.1017/CBO9780511977381))
-  Modern Fortran - Building Efficient Parallel Applications ([https://www.manning.com/books/modern-fortran](https://www.manning.com/books/modern-fortran))
-  Modern Fortran Explained - Incorporating Fortran 2018 ([Amazon](https://www.amazon.com/Modern-Fortran-Explained-Incorporating-Mathematics/dp/0198811896))
