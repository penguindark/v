/*
regex 2.0 alpha

Copyright (c) 2019-2022 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.
*/
module regex

//import strings

/******************************************************************************
*
* Inits
*
******************************************************************************/
// regex create a regex object from the query string, retunr RE object and errors as re_err, err_pos
pub fn regex_base(pattern string) (RE, int, int) {
	// init regex
	mut re := RE{}
	re.prog = []Token{len: pattern.len + 1} // max program length, can not be longer then the pattern
	re.cc = []CharClass{len: pattern.len} // can not be more char class the the length of the pattern
	re.groups_pc = []int{len: pattern.len/2, init:-1}
	re_err, err_pos := re.impl_compile(pattern, 0, 0)
	return re, re_err, err_pos
}