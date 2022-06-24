module regex

import strings

// new_regex create a RE of small size, usually sufficient for ordinary use
pub fn new() RE {
	// init regex
	mut re := RE{}
	re.prog = []Token{len: 1} // max program length, can not be longer then the pattern
	re.cc = []CharClass{len: max_code_len} // can not be more char class the the length of the pattern
	
	//re.group_stack = []int{len: re.group_max, init: -1}
	//re.group_data = []int{len: re.group_max, init: -1}

	return re
}

// compile_opt compile RE pattern string
pub fn (mut re RE) compile_opt(pattern string) ? {
	re_err, err_pos := re.impl_compile(pattern, 0, 0)

	if re_err != compile_ok {
		mut err_msg := strings.new_builder(300)
		err_msg.write_string('\nquery: $pattern\n')
		line := '-'.repeat(err_pos)
		err_msg.write_string('err  : $line^\n')
		err_str := re.get_parse_error_string(re_err)
		err_msg.write_string('ERROR: $err_str\n')
		return error_with_code(err_msg.str(), re_err)
	}
}

// regex_opt create new RE object from RE pattern string
pub fn regex_opt(pattern string) ?RE {
	// init regex
	mut re := RE{}
	
	re.prog = []Token{len: pattern.len/2 + 1} // max program length, can not be longer then the pattern
	re.cc = []CharClass{len: pattern.len} // can not be more char class the the length of the pattern
	
	// compile the pattern
	re.compile_opt(pattern) ?

	return re
}