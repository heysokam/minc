int main(void) {
  void* t00                      = nullptr;
  t00                            = nullptr;
  float t01                      = 1.0f;
  t01                            = 2.0f;
  float t02                      = 1.0f;
  t02                            = 2.0f;
  double t03                     = 1.0;
  t03                            = 2.0;
  long double t04                = 1.0L;
  t04                            = 2.0L;
  i8 t05                         = 1;
  t05                            = 2;
  i16 t06                        = 1;
  t06                            = 2;
  i32 t07                        = 1;
  t07                            = 2;
  i64 t08                        = 1;
  t08                            = 2;
  int t09                        = 1;
  t09                            = 2;
  u8 t10                         = 1;
  t10                            = 2;
  u16 t11                        = 1;
  t11                            = 2;
  u32 t12                        = 1;
  t12                            = 2;
  u64 t13                        = 1;
  t13                            = 2;
  uint t14                       = 1;
  t14                            = 2;
  char t15                       = 'a';
  t15                            = 'B';
  char* t16                      = "asd";
  t16                            = "fgh";
  char* t17                      = "asd";
  t17                            = "fgh";
  char* t18                      = "Line1\n"
                                   "Line2\n";
  t18                            = "inline TripleStrLit";
  t18                            = "some raw inline TripleStrLit";
  int                     t19[1] = { 0 };
  /*constexpr*/ int const forty2 = 42;
  return forty2;
}