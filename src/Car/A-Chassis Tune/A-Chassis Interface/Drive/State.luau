-- Live drive state shared by the Drive modules (B-Chassis kept it as ~100 upvalues in one script).
-- Drive's init fills it before requiring any module; plugins may read it, but only Drive writes it.
return {} :: { [string]: any }
