/*
regex 2.0 alpha

Copyright (c) 2019-2022 Dario Deledda. All rights reserved.
Use of this source code is governed by an MIT license
that can be found in the LICENSE file.

This file contains regex module

Know limitation:
- find is implemented in a trivial way
- not full compliant PCRE
- not compliant POSIX ERE
*/
module regex

import strings

pub const (
	v_regex_version          = '2.0 alpha' // regex module version
	max_quantifier           = 2147483648 // default max repetitions allowed for the quantifiers = 2^31
	max_code_len             = 256 // defualt max code length
	// spaces chars (here only westerns!!) TODO: manage all the spaces from unicode
	spaces                   = [` `, `\t`, `\n`, `\r`, `\v`, `\f`]
	// new line chars for now only '\n'
	new_line_list            = [`\n`, `\r`]

	// Results
	no_match_found           = -1

	// Errors
	compile_ok               = 0 // the regex string compiled, all ok
	program_end_ok           = -2 // the program if fished, match ok
	err_char_unknown         = -3 // the char used is unknow to the system
	err_undefined            = -4 // the compiler symbol is undefined
	err_internal_error       = -5 // Bug in the regex system!!
	err_cc_alloc_overflow    = -6 // memory for char class full!!
	err_syntax_error         = -7 // syntax error in regex compiling
	err_groups_overflow      = -8 // max number of groups reached
	err_groups_max_nested    = -9 // max number of nested group reached
	err_group_not_balanced   = -10 // group not balanced
	err_group_qm_notation    = -11 // group invalid notation
	err_invalid_or_with_cc   = -12 // invalid or on two consecutive char class
	err_neg_group_quantifier = -13 // negation groups can not have quantifier
)

const (
	//*************************************
	// regex program instructions
	//*************************************
	ist_simple_char    = 0x00000001 // single char instruction, 31 bit available to char
	ist_char_class_pos = 0x00000002 // char class normal [abc]
	ist_char_class_neg = 0x00000003 // char class negate [^abc]
	ist_dot_char       = 0x00000004 // match any char except \n
	ist_bsls_char      = 0x00000005 // backslash char
	// groups          
	ist_group_start    = 0x00000006 // group start (
	ist_group_end      = 0x00000007 // group end   )
	// control instructions
	ist_prog_end       = 0x00000008 // end the program

	//*************************************
)

/******************************************************************************
*
* General Utilities
*
******************************************************************************/
// utf8util_rune_len calculate the length in bytes of a utf8 rune
[inline]
fn utf8util_rune_len(b u8) int {
	return ((0xe5000000 >> ((b >> 3) & 0x1e)) & 3) + 1
}

// get_rune get a rune from position i and return an u32 with the unicode code
[direct_array_access; inline]
fn (re RE) get_rune(in_txt string, i int) (u32, int) {
	ini := unsafe { in_txt.str[i] }
	// ascii 8 bit
	if (re.flag & regex.f_bin) != 0 || ini & 0x80 == 0 {
		return u32(ini), 1
	}
	// unicode char
	char_len := utf8util_rune_len(ini)
	mut tmp := 0
	mut ch := u32(0)
	for tmp < char_len {
		ch = (ch << 8) | unsafe { in_txt.str[i + tmp] }
		tmp++
	}
	return ch, char_len
}

// get_runeb get a rune from position i and return an u32 with the unicode code
[direct_array_access; inline]
fn (re RE) get_runeb(in_txt &u8, i int) (u32, int) {
	// ascii 8 bit
	if (re.flag & regex.f_bin) != 0 || unsafe { in_txt[i] } & 0x80 == 0 {
		return u32(unsafe { in_txt[i] }), 1
	}
	// unicode char
	char_len := utf8util_rune_len(unsafe { in_txt[i] })
	mut tmp := 0
	mut ch := u32(0)
	for tmp < char_len {
		ch = (ch << 8) | unsafe { in_txt[i + tmp] }
		tmp++
	}
	return ch, char_len
}

[inline]
fn is_alnum(in_char u8) bool {
	mut tmp := in_char - `A`
	if tmp <= 25 {
		return true
	}
	tmp = in_char - `a`
	if tmp <= 25 {
		return true
	}
	tmp = in_char - `0`
	if tmp <= 9 {
		return true
	}
	if in_char == `_` {
		return true
	}
	return false
}

[inline]
fn is_not_alnum(in_char u8) bool {
	return !is_alnum(in_char)
}

[inline]
fn is_space(in_char u8) bool {
	return in_char in regex.spaces
}

[inline]
fn is_not_space(in_char u8) bool {
	return !is_space(in_char)
}

[inline]
fn is_digit(in_char u8) bool {
	tmp := in_char - `0`
	return tmp <= 0x09
}

[inline]
fn is_not_digit(in_char u8) bool {
	return !is_digit(in_char)
}

[inline]
fn is_lower(in_char u8) bool {
	tmp := in_char - `a`
	return tmp <= 25
}

[inline]
fn is_upper(in_char u8) bool {
	tmp := in_char - `A`
	return tmp <= 25
}

pub fn (re RE) get_parse_error_string(err int) string {
	match err {
		regex.compile_ok { return 'compile_ok' }
		regex.no_match_found { return 'no_match_found' }
		regex.err_char_unknown { return 'err_char_unknown' }
		regex.err_undefined { return 'err_undefined' }
		regex.err_internal_error { return 'err_internal_error' }
		regex.err_cc_alloc_overflow { return 'err_cc_alloc_overflow' }
		regex.err_syntax_error { return 'err_syntax_error' }
		regex.err_groups_overflow { return 'err_groups_overflow' }
		regex.err_groups_max_nested { return 'err_groups_max_nested' }
		regex.err_group_not_balanced { return 'err_group_not_balanced' }
		regex.err_group_qm_notation { return 'err_group_qm_notation' }
		regex.err_invalid_or_with_cc { return 'err_invalid_or_with_cc' }
		regex.err_neg_group_quantifier { return 'err_neg_group_quantifier' }
		else { return 'err_unknown' }
	}
}

// utf8_str convert and utf8 sequence to a printable string
[inline]
fn utf8_str(ch rune) string {
	mut i := 4
	mut res := ''
	for i > 0 {
		v := u8((ch >> ((i - 1) * 8)) & 0xFF)
		if v != 0 {
			res += '${v:1c}'
		}
		i--
	}
	return res
}

// simple_log default log function
fn simple_log(txt string) {
	print(txt)
}

/******************************************************************************
*
* Token Structs
*
******************************************************************************/
pub type FnValidator = fn (u8) bool

struct Token {
mut:
	ist u32
	// char
	ch     rune // char of the token if any
	// Quantifiers / branch
	rep_min i64  // used also for jump next in the OR branch [no match] pc jump
	rep_max i64  // used also for jump next in the OR branch [   match] pc jump
	greedy  bool // greedy quantifier flag
	// Char class
	cc_index int = -1
	// counters for quantifier check (repetitions)
	rep int
	// validator function pointer
	validator FnValidator
	
	// groups variables
	group_capture bool = true // if false the group is not captured
	group_neg bool // negation flag for the group, 0 => no negation > 0 => negataion
	group_id  int = -1 // id of the group
	jmp_pc    int = -1
	group_start int = -1
	group_end   int = -1

	// section row index
	row_i   int = -1 // row to execute if dot or group
	// or flag
	or_flag bool  // if true this token has nan OR escape 
}
/******************************************************************************
*
* RE structs
*
******************************************************************************/
pub const (
	f_nl  = 0x00000001 // end the match when find a new line symbol
	f_ms  = 0x00000002 // match true only if the match is at the start of the string
	f_me  = 0x00000004 // match true only if the match is at the end of the string

	f_efm = 0x00000100 // exit on first token matched, used by search
	f_bin = 0x00000200 // work only on bytes, ignore utf-8
	// behaviour modifier flags
	f_src = 0x00020000 // search mode enabled
)


// Log function prototype
pub type FnLog = fn (string)

pub struct RE {
pub mut:
	prog []Token // regex program
	
	// char classes storage
	cc       []CharClass // char class list
	cc_index int // index
	// groups
	group_count      int   // number of groups in this regex struct
	groups           []int // groups index results
	group_index      map[string]int // group name to index
	group_name       []string // group name by index

	groups_pc        []int

	// flags
	flag int // flag for optional parameters
	// Debug/log
	debug    int    // enable in order to have the unroll of the code 0 = NO_DEBUG, 1 = LIGHT 2 = VERBOSE 3 = MAX LOG
	log_func FnLog = simple_log // log function, can be customized by the user
	query    string // query string

	call_level int
}

/******************************************************************************
*
* Backslashes chars
*
******************************************************************************/
struct BslsStruct {
	ch        rune        // meta char
	validator FnValidator // validator function pointer
}

const (
	bsls_validator_array = [
		BslsStruct{`w`, is_alnum},
		BslsStruct{`W`, is_not_alnum},
		BslsStruct{`s`, is_space},
		BslsStruct{`S`, is_not_space},
		BslsStruct{`d`, is_digit},
		BslsStruct{`D`, is_not_digit},
		BslsStruct{`a`, is_lower},
		BslsStruct{`A`, is_upper},
	]

	// these chars are escape if preceded by a \
	bsls_escape_list     = [`\\`, `|`, `.`, `:`, `*`, `+`, `-`, `{`, `}`, `[`, `]`, `(`, `)`, `?`,
		`^`, `!`]
)

enum BSLS_parse_state {
	start
	bsls_found
	bsls_char
	normal_char
}

// parse_bsls return (index, str_len) bsls_validator_array index, len of the backslash sequence if present
fn (re RE) parse_bsls(in_txt string, in_i int) (int, int) {
	mut status := BSLS_parse_state.start
	mut i := in_i

	for i < in_txt.len {
		// get our char
		char_tmp, char_len := re.get_rune(in_txt, i)
		ch := u8(char_tmp)

		if status == .start && ch == `\\` {
			status = .bsls_found
			i += char_len
			continue
		}

		// check if is our bsls char, for now only one length sequence
		if status == .bsls_found {
			for c, x in regex.bsls_validator_array {
				if x.ch == ch {
					return c, i - in_i + 1
				}
			}
			status = .normal_char
			continue
		}

		// no BSLS validator, manage as normal escape char char
		if status == .normal_char {
			if ch in regex.bsls_escape_list {
				return regex.no_match_found, i - in_i + 1
			}
			return regex.err_syntax_error, i - in_i + 1
		}

		// at the present time we manage only one char after the \
		break
	}
	// not our bsls return KO
	return regex.err_syntax_error, i
}

/******************************************************************************
*
* Char class
*
******************************************************************************/
const (
	cc_null = 0 // empty cc token
	cc_char = 1 // simple char: a
	cc_int  = 2 // char interval: a-z
	cc_bsls = 3 // backslash char
	cc_end  = 4 // cc sequence terminator
)

struct CharClass {
mut:
	cc_type   int = regex.cc_null // type of cc token
	ch0       rune        // first char of the interval a-b  a in this case
	ch1       rune        // second char of the interval a-b b in this case
	validator FnValidator // validator function pointer
}

enum CharClass_parse_state {
	start
	in_char
	in_bsls
	separator
	finish
}

fn (re RE) get_char_class(level int, pc int) string {
	buf := []u8{len: (re.cc.len)}
	mut buf_ptr := unsafe { &u8(&buf) }

	mut cc_i := re.prog[pc].cc_index
	mut i := 0
	mut tmp := 0
	for cc_i >= 0 && cc_i < re.cc.len && re.cc[cc_i].cc_type != regex.cc_end {
		if re.cc[cc_i].cc_type == regex.cc_bsls {
			unsafe {
				buf_ptr[i] = `\\`
				i++
				buf_ptr[i] = u8(re.cc[cc_i].ch0)
				i++
			}
		} else if re.cc[cc_i].ch0 == re.cc[cc_i].ch1 {
			tmp = 3
			for tmp >= 0 {
				x := u8((re.cc[cc_i].ch0 >> (tmp * 8)) & 0xFF)
				if x != 0 {
					unsafe {
						buf_ptr[i] = x
						i++
					}
				}
				tmp--
			}
		} else {
			tmp = 3
			for tmp >= 0 {
				x := u8((re.cc[cc_i].ch0 >> (tmp * 8)) & 0xFF)
				if x != 0 {
					unsafe {
						buf_ptr[i] = x
						i++
					}
				}
				tmp--
			}
			unsafe {
				buf_ptr[i] = `-`
				i++
			}
			tmp = 3
			for tmp >= 0 {
				x := u8((re.cc[cc_i].ch1 >> (tmp * 8)) & 0xFF)
				if x != 0 {
					unsafe {
						buf_ptr[i] = x
						i++
					}
				}
				tmp--
			}
		}
		cc_i++
	}
	unsafe {
		buf_ptr[i] = u8(0)
	}
	return unsafe { tos_clone(buf_ptr) }
}


fn (re RE) check_char_class(pc int, ch rune) bool {
	mut cc_i := re.prog[pc].cc_index
	for cc_i >= 0 && cc_i < re.cc.len && re.cc[cc_i].cc_type != regex.cc_end {
		if re.cc[cc_i].cc_type == regex.cc_bsls {
			if re.cc[cc_i].validator(u8(ch)) {
				return true
			}
		} else if ch >= re.cc[cc_i].ch0 && ch <= re.cc[cc_i].ch1 {
			return true
		}
		cc_i++
	}
	return false
}


// parse_char_class return (index, str_len, cc_type) of a char class [abcm-p], char class start after the [ char
fn (mut re RE) parse_char_class(in_txt string, in_i int) (int, int, u32) {
	mut status := CharClass_parse_state.start
	mut i := in_i

	mut tmp_index := re.cc_index
	res_index := re.cc_index

	mut cc_type := u32(regex.ist_char_class_pos)

	for i < in_txt.len {
		// check if we are out of memory for char classes
		if tmp_index >= re.cc.len {
			return regex.err_cc_alloc_overflow, 0, u32(0)
		}

		// get our char
		char_tmp, char_len := re.get_rune(in_txt, i)
		ch := u8(char_tmp)

		// println("CC #${i:3d} ch: ${ch:c}")

		// negation
		if status == .start && ch == `^` {
			cc_type = u32(regex.ist_char_class_neg)
			i += char_len
			continue
		}

		// minus symbol
		if status == .start && ch == `-` {
			re.cc[tmp_index].cc_type = regex.cc_char
			re.cc[tmp_index].ch0 = char_tmp
			re.cc[tmp_index].ch1 = char_tmp
			i += char_len
			tmp_index++
			continue
		}

		// bsls
		if (status == .start || status == .in_char) && ch == `\\` {
			// println("CC bsls.")
			status = .in_bsls
			i += char_len
			continue
		}

		if status == .in_bsls {
			// println("CC bsls validation.")
			for c, x in regex.bsls_validator_array {
				if x.ch == ch {
					// println("CC bsls found [${ch:c}]")
					re.cc[tmp_index].cc_type = regex.cc_bsls
					re.cc[tmp_index].ch0 = regex.bsls_validator_array[c].ch
					re.cc[tmp_index].ch1 = regex.bsls_validator_array[c].ch
					re.cc[tmp_index].validator = regex.bsls_validator_array[c].validator
					i += char_len
					tmp_index++
					status = .in_char
					break
				}
			}
			if status == .in_bsls {
				// manage as a simple char
				// println("CC bsls not found [${ch:c}]")
				re.cc[tmp_index].cc_type = regex.cc_char
				re.cc[tmp_index].ch0 = char_tmp
				re.cc[tmp_index].ch1 = char_tmp
				i += char_len
				tmp_index++
				status = .in_char
				continue
			} else {
				continue
			}
		}

		// simple char
		if (status == .start || status == .in_char) && ch != `-` && ch != `]` {
			status = .in_char

			re.cc[tmp_index].cc_type = regex.cc_char
			re.cc[tmp_index].ch0 = char_tmp
			re.cc[tmp_index].ch1 = char_tmp

			i += char_len
			tmp_index++
			continue
		}

		// check range separator
		if status == .in_char && ch == `-` {
			status = .separator
			i += char_len
			continue
		}

		// check range end
		if status == .separator && ch != `]` && ch != `-` {
			status = .in_char
			re.cc[tmp_index - 1].cc_type = regex.cc_int
			re.cc[tmp_index - 1].ch1 = char_tmp
			i += char_len
			continue
		}

		// char class end
		if status == .in_char && ch == `]` {
			re.cc[tmp_index].cc_type = regex.cc_end
			re.cc[tmp_index].ch0 = 0
			re.cc[tmp_index].ch1 = 0
			re.cc_index = tmp_index + 1

			return res_index, i - in_i + 2, cc_type
		}

		i++
	}
	return regex.err_syntax_error, 0, u32(0)
}


/******************************************************************************
*
* Quantifier
*
******************************************************************************/
enum Quant_parse_state {
	start
	min_parse
	comma_checked
	max_parse
	greedy
	gredy_parse
	finish
}

// parse_quantifier return (min, max, str_len, greedy_flag) of a {min,max}? quantifier starting after the { char
fn (re RE) parse_quantifier(in_txt string, in_i int) (int, int, int, bool) {
	mut status := Quant_parse_state.start
	mut i := in_i

	mut q_min := 0 // default min in a {} quantifier is 1
	mut q_max := 0 // deafult max in a {} quantifier is max_quantifier

	mut ch := u8(0)

	for i < in_txt.len {
		unsafe {
			ch = in_txt.str[i]
		}
		// println("${ch:c} status: $status")

		// exit on no compatible char with {} quantifier
		if utf8util_rune_len(ch) != 1 {
			return regex.err_syntax_error, i, 0, false
		}

		// min parsing skip if comma present
		if status == .start && ch == `,` {
			q_min = 0 // default min in a {} quantifier is 0
			status = .comma_checked
			i++
			continue
		}

		if status == .start && is_digit(ch) {
			status = .min_parse
			q_min *= 10
			q_min += int(ch - `0`)
			i++
			continue
		}

		if status == .min_parse && is_digit(ch) {
			q_min *= 10
			q_min += int(ch - `0`)
			i++
			continue
		}

		// we have parsed the min, now check the max
		if status == .min_parse && ch == `,` {
			status = .comma_checked
			i++
			continue
		}

		// single value {4}
		if status == .min_parse && ch == `}` {
			q_max = q_min
			status = .greedy
			continue
		}

		// end without max
		if status == .comma_checked && ch == `}` {
			q_max = regex.max_quantifier
			status = .greedy
			continue
		}

		// start max parsing
		if status == .comma_checked && is_digit(ch) {
			status = .max_parse
			q_max *= 10
			q_max += int(ch - `0`)
			i++
			continue
		}

		// parse the max
		if status == .max_parse && is_digit(ch) {
			q_max *= 10
			q_max += int(ch - `0`)
			i++
			continue
		}

		// finished the quantifier
		if status == .max_parse && ch == `}` {
			status = .greedy
			continue
		}

		// check if greedy flag char ? is present
		if status == .greedy {
			if i + 1 < in_txt.len {
				i++
				status = .gredy_parse
				continue
			}
			return q_min, q_max, i - in_i + 2, false
		}

		// check the greedy flag
		if status == .gredy_parse {
			if ch == `?` {
				return q_min, q_max, i - in_i + 2, true
			} else {
				i--
				return q_min, q_max, i - in_i + 2, false
			}
		}

		// not  a {} quantifier, exit
		return regex.err_syntax_error, i, 0, false
	}

	// not a conform {} quantifier
	return regex.err_syntax_error, i, 0, false
}

/******************************************************************************
*
* Groups
*
******************************************************************************/
enum Group_parse_state {
	start
	q_mark // (?
	q_mark1 // (?:|P  checking
	p_status // (?P
	p_start // (?P<
	p_end // (?P<...>
	p_in_name // (?P<...
	finish
}

// parse_groups parse a group for ? (question mark) syntax, if found, return (error, capture_flag, negate_flag, name_of_the_group, next_index)
fn (re RE) parse_groups(in_txt string, in_i int) (int, bool, bool, string, int) {
	mut status := Group_parse_state.start
	mut i := in_i
	mut name := ''

	for i < in_txt.len && status != .finish {
		// get our char
		char_tmp, char_len := re.get_rune(in_txt, i)
		ch := u8(char_tmp)

		// start
		if status == .start && ch == `(` {
			status = .q_mark
			i += char_len
			continue
		}

		// check for question marks
		if status == .q_mark && ch == `?` {
			status = .q_mark1
			i += char_len
			continue
		}

		// negate group
		if status == .q_mark1 && ch == `!` {
			i += char_len
			return 0, false, true, name, i
		}

		// non capturing group
		if status == .q_mark1 && ch == `:` {
			i += char_len
			return 0, false, false, name, i
		}

		// enter in P section
		if status == .q_mark1 && ch == `P` {
			status = .p_status
			i += char_len
			continue
		}

		// not a valid q mark found
		if status == .q_mark1 {
			// println("NO VALID Q MARK")
			return -2, true, false, name, i
		}

		if status == .p_status && ch == `<` {
			status = .p_start
			i += char_len
			continue
		}

		if status == .p_start && ch != `>` {
			status = .p_in_name
			name += '${ch:1c}' // TODO: manage utf8 chars
			i += char_len
			continue
		}

		// colect name
		if status == .p_in_name && ch != `>` && is_alnum(ch) {
			name += '${ch:1c}' // TODO: manage utf8 chars
			i += char_len
			continue
		}

		// end name
		if status == .p_in_name && ch == `>` {
			i += char_len
			return 0, true, false, name, i
		}

		// error on name group
		if status == .p_in_name {
			return -2, true, false, name, i
		}

		// normal group, nothig to do, exit
		return 0, true, false, name, i
	}
	// UNREACHABLE
	// println("ERROR!! NOT MEANT TO BE HERE!!1")
	return -2, true, false, name, i
}

/******************************************************************************
*
* Compiler
*
******************************************************************************/
const (
	quntifier_chars = [rune(`+`), `*`, `?`, `{`]
)

//
// main compiler
//

fn (mut re RE) compile_section(in_txt string, in_txt_pos int, level int) (int, int) {
	mut i := in_txt_pos // input string index
	mut pc := 0 // section ist counter
	mut row := []Token{}

	re.groups_pc << -1
	for i < in_txt.len {
		mut char_tmp := u32(0)
		mut char_len := 0
		// println("i: ${i:3d} ch: ${in_txt.str[i]:c}")

		char_tmp, char_len = re.get_rune(in_txt, i)

		//
		// check special cases: $ ^
		//
		//println("char[${char_tmp:c}]")
		if (char_len == 1) && (i == 0) && (u8(char_tmp) == `^`) {
			re.flag |= regex.f_ms
			i = i + char_len
			continue
		}
		if (char_len == 1) && (i == (in_txt.len - 1)) && (u8(char_tmp) == `$`) {
			re.flag |= regex.f_me
			i = i + char_len
			continue
		}

		// ist_group_start
		if char_len == 1 && pc >= 0 && u8(char_tmp) == `(` {
			// println("Group start")
			group_res, cgroup_flag, negate_flag, cgroup_name, next_i := re.parse_groups(in_txt, i)
			//println("group_res: $group_res cgroup_flag: $cgroup_flag negate_flag: $negate_flag cgroup_name: [$cgroup_name] next_i: $next_i")

			// manage question mark format error
			if group_res < -1 {
				return regex.err_group_qm_notation, next_i
			}

			re.group_count++
			mut t := Token{}
			t.ist = u32(0) | regex.ist_group_start
			t.rep_min = 1
			t.rep_max = 1
			t.row_i = re.group_count
			t.group_capture = cgroup_flag
			t.group_neg = negate_flag
			row << t

			if cgroup_name.len > 0 {
				re.group_index[cgroup_name] = t.row_i
			}
			
			re.groups_pc[re.group_count]=row.len - 1
			pc = pc + 1
			
			i = next_i
			//println("pos: ${i}")		
			//println("res: ${res} res_pos: ${res_pos} lev: ${t.row_i}")
			continue
		}

		// ist_group_end
		if char_len == 1 && pc >= 0 && u8(char_tmp) == `)` {
			// println("Group end")
			i = i + char_len

			group_start_pc := re.groups_pc[re.group_count]
			mut t := Token{}
			t.ist = u32(0) | regex.ist_group_end
			t.row_i = re.group_count
			t.rep_min = row[group_start_pc].rep_min
			t.rep_max = row[group_start_pc].rep_max
			t.jmp_pc = group_start_pc
			row << t
			pc = pc + 1
			continue
		}

		// Quantifiers
		if char_len == 1 && pc > 0 {
			mut char_next := rune(0)
			mut char_next_len := 0
			if (char_len + i) < in_txt.len {
				char_next, char_next_len = re.get_rune(in_txt, i + char_len)
			}
			mut quant_flag := true

			// negation groups can not have quantifiers
			if row[pc - 1].group_neg == true && char_tmp in [`?`, `+`, `*`, `{`] {
				return regex.err_neg_group_quantifier, i
			}

			match u8(char_tmp) {
				`?` {
					// println("q: ${char_tmp:c}")
					// check illegal quantifier sequences
					if char_next_len == 1 && char_next in regex.quntifier_chars {
						return regex.err_syntax_error, i
					}
					row[pc - 1].rep_min = 0
					row[pc - 1].rep_max = 1
				}
				`+` {
					// println("q: ${char_tmp:c}")
					// check illegal quantifier sequences
					if char_next_len == 1 && char_next in regex.quntifier_chars {
						return regex.err_syntax_error, i
					}
					row[pc - 1].rep_min = 1
					row[pc - 1].rep_max = regex.max_quantifier
				}
				`*` {
					// println("q: ${char_tmp:c}")
					// check illegal quantifier sequences
					if char_next_len == 1 && char_next in regex.quntifier_chars {
						return regex.err_syntax_error, i
					}
					row[pc - 1].rep_min = 0
					row[pc - 1].rep_max = regex.max_quantifier
				}
				`{` {
					min, max, tmp, greedy := re.parse_quantifier(in_txt, i + 1)
					// it is a quantifier
					if min >= 0 {
						// println("{$min,$max}\n str:[${in_txt[i..i+tmp]}] greedy:$greedy")
						i = i + tmp
						row[pc - 1].rep_min = min
						row[pc - 1].rep_max = max
						row[pc - 1].greedy = greedy
						// check illegal quantifier sequences
						if i <= in_txt.len {
							char_next, char_next_len = re.get_rune(in_txt, i)
							if char_next_len == 1 && char_next in regex.quntifier_chars {
								return regex.err_syntax_error, i
							}
						}
						continue
					} else {
						return min, i
					}

					// TODO: decide if the open bracket can be conform without the close bracket
					/*
					// no conform, parse as normal char
					else {
						quant_flag = false
					}
					*/
				}
				else {
					quant_flag = false
				}
			}

			if quant_flag {
				i = i + char_len
				continue
			}
		}

		// IST_DOT_CHAR
		if char_len == 1 && pc >= 0 && u8(char_tmp) == `.` {
			// consecutive ist_dot_char is a syntax error
			mut t := Token{}
			t.ist = u32(0) | regex.ist_dot_char
			t.rep_min = 1
			t.rep_max = 1
			row << t
			pc = pc + 1
			i = i + char_len
			continue
		}

		// IST_CHAR_CLASS_*
		if char_len == 1 && pc >= 0 {
			if u8(char_tmp) == `[` {
				cc_index, tmp, cc_type := re.parse_char_class(in_txt, i + 1)
				if cc_index >= 0 {
					// println("index: $cc_index str:${in_txt[i..i+tmp]}")
					i = i + tmp
					mut t := Token{}
					t.ist = u32(0) | cc_type
					t.cc_index = cc_index
					t.rep_min = 1
					t.rep_max = 1
					row << t
					pc = pc + 1
					continue
				}
				// cc_class vector memory full, return the error
				else if cc_index < 0 {
					return cc_index, i
				}
			}
		}

		// OR
		if char_len == 1 && pc > 0 && u8(char_tmp) == `|` {		
			// OR as last operation is a syntax error
			if i >= (in_txt.len-1) {
				return regex.err_syntax_error, i
			}
			
			// multiple OR in sequence is a syntax error
			if pc - 1 >= 0 && row[pc - 1].or_flag == true {
				return regex.err_syntax_error, i
			}
			row[pc - 1].or_flag = true
			i = i + char_len
			continue
		}

		// ist_bsls_char
		if char_len == 1 && pc >= 0 {
			if u8(char_tmp) == `\\` {
				bsls_index, tmp := re.parse_bsls(in_txt, i)
				// println("index: $bsls_index str:${in_txt[i..i+tmp]}")
				if bsls_index >= 0 {
					i = i + tmp
					mut t := Token{}
					t.ist = u32(0) | regex.ist_bsls_char
					t.rep_min = 1
					t.rep_max = 1
					t.validator = regex.bsls_validator_array[bsls_index].validator
					t.ch = regex.bsls_validator_array[bsls_index].ch
					row << t
					pc = pc + 1
					continue
				}
				// this is an escape char, skip the bsls and continue as a normal char
				else if bsls_index == regex.no_match_found {
					i += char_len
					char_tmp, char_len = re.get_rune(in_txt, i)
					// continue as simple char
				}
				// if not an escape or a bsls char then it is an error (at least for now!)
				else {
					return bsls_index, i + tmp
				}
			}
		}

		// ist_simple_char
		mut t := Token{}
		t.ist = regex.ist_simple_char
		t.ch = char_tmp
		t.rep_min = 1
		t.rep_max = 1
		row << t
		//println("${i}:${in_txt.len} char: ${char_tmp:c} charlen:${char_len}")
		pc = pc + 1
		i += char_len
	}

	//if level == 0 {
	mut t := Token{}
	t.ist = regex.ist_prog_end
	row << t
	//}

	re.prog = row
	return regex.compile_ok, i
}

// compile return (return code, index) where index is the index of the error in the query string if return code is an error code
fn (mut re RE) impl_compile(in_txt string, in_txt_pos int, level int) (int, int) {
	re.groups_pc = []int{len:in_txt.len,init: -1}
	res, res_pos := re.compile_section(in_txt, 0, 0)
	// init Groups
	re.groups = []int{len:(re.group_count + 1) * 2, init: -1 }
	re.group_name = []string{len:(re.group_count + 1)}

	for k,v in re.group_index {
		re.group_name[v] = k
	}

	//******************************************
	// DEBUG PRINT REGEX GENERATED CODE
	//******************************************
	/*
	if re.debug > 0 {
		gc := re.get_code()
		re.log_func(gc)
	}
	*/
	//******************************************

	return res, res_pos
}

// get_code return the compiled code as regex string, note: may be different from the source!
pub fn (re RE) get_code() string {
	return ""
}

// get_query return a string with a reconstruction of the query starting from the regex program code
pub fn (re RE) get_query() string {
	mut res := strings.new_builder(re.query.len * 2)
	
	if (re.flag & regex.f_ms) != 0 {
		res.write_string('^')
	}
	
	re.get_query_int(mut res, 0)
	
	if (re.flag & regex.f_me) != 0 {
		res.write_string('$')
	}

	return res.str()
}

fn get_quantifier_string(mut res strings.Builder, tk Token){
	// quantifier
	if !(tk.rep_min == 1 && tk.rep_max == 1) && tk.group_neg == false {
		if tk.rep_min == 0 && tk.rep_max == 1 {
			res.write_string('?')
		} else if tk.rep_min == 1 && tk.rep_max == regex.max_quantifier {
			res.write_string('+')
		} else if tk.rep_min == 0 && tk.rep_max == regex.max_quantifier {
			res.write_string('*')
		} else {
			if tk.rep_max == regex.max_quantifier {
				res.write_string('{$tk.rep_min,MAX}')
			} else {
				res.write_string('{$tk.rep_min,$tk.rep_max}')
			}
			if tk.greedy == true {
				res.write_string('?')
			}
		}
	}
	if tk.or_flag == true {
		res.write_string('|')
	}
}

fn get_debug_quantifier_string(tk Token, rep int) string {
	mut res := strings.new_builder(64)
	res.write_string('rep: ${rep} in ')
	if tk.rep_max == regex.max_quantifier {
		res.write_string('{$tk.rep_min,MAX}')
	} else {
		res.write_string('{$tk.rep_min,$tk.rep_max}')
	}
	
	if tk.greedy == true {
		res.write_string('?')
	}

	if tk.or_flag == true {
		res.write_string(' OR ')
	}
	return res.str()
}

fn (re RE) get_query_int(mut res strings.Builder, level int) {
	if level < 0 || level >= re.prog.len {
		return
	}
	for c, tk in re.prog {
		ist := tk.ist
/*
		if ist == regex.ist_prog_end {
			res.write_string("[**END**]")
		}
*/
		// char class
		if ist == regex.ist_char_class_neg || ist == regex.ist_char_class_pos {
			res.write_string('[')
			if ist == regex.ist_char_class_neg {
				res.write_string('^')
			}
			res.write_string('${re.get_char_class(level, c)}')
			res.write_string(']')
			get_quantifier_string(mut res, tk)
		}

		// bsls char
		else if ist == regex.ist_bsls_char {
			res.write_string('\\${tk.ch:1c}')
			get_quantifier_string(mut res, tk)
		}

		// ist_dot_char
		else if ist == regex.ist_dot_char {
			res.write_string('.')
			get_quantifier_string(mut res, tk)
		}

		// char alone
		else if ist == regex.ist_simple_char {
			if u8(ist) in regex.bsls_escape_list {
				res.write_string('\\')
			}
			res.write_string('${tk.ch:c}')
			get_quantifier_string(mut res, tk)
		}

		// groups
		else if ist == regex.ist_group_start {
			res.write_string('(')
			if tk.group_capture == false {
				res.write_string('?:')
			}
			else if re.group_name[tk.row_i].len > 0 {
				res.write_string('?P<${re.group_name[tk.row_i]}>')
			}
		}
		else if ist == regex.ist_group_end {
			res.write_string(')')
			get_quantifier_string(mut res, tk)
		}
	}
}

/******************************************************************************
*
* Matching
*
******************************************************************************/
//[direct_array_access]
pub fn (mut re RE) match_base(in_txt &u8, in_i int, in_txt_len int, in_level int, in_pc int) (int, int) {
	if re.debug > 1 {
		unsafe{
			println("txt:{${tos(in_txt, in_i)}}[${tos(in_txt+in_i, in_txt_len -in_i)}]")
		}
	}
	re.call_level++

	mut ch := rune(0) // examinated char
	mut char_len := 0 // utf8 examinated char len

	mut i := in_i
	mut pc := in_pc // program counter
	mut rep := 0
	mut tk := &re.prog[in_pc]

	mut level := in_level

	//println("match_base lev:${level}")
	
	// first rune loaded
	ch, char_len = re.get_runeb(in_txt, i)

	for i < in_txt_len && pc < re.prog.len {
		// get token
		tk = &re.prog[pc]
		// segment end, exit!
		if tk.ist == regex.ist_prog_end {
			break
		}
		
		// println("ist: ${tk.ist:8x}")
		// load the next rune
		ch, char_len = re.get_runeb(in_txt, i)

		if re.debug > 0 {
			print("lvl: ${re.call_level:2}:${level:2} pc: ${pc:3}/${re.prog.len - 1:3} ")
			quant := get_debug_quantifier_string(tk, rep)
			match tk.ist {
				regex.ist_prog_end {
					println("[ENDP] ")
				}
				regex.ist_simple_char { 
					println("[RUNE] i:${i} [${tk.ch}] == [${ch}] => ${tk.ch == ch} ${quant}")
				}
				regex.ist_char_class_pos {
					// check the CC
					cc_res := re.check_char_class(pc, ch)
					println("[CC  ] i:${i} neg:false ${i}: [${re.get_char_class(level, pc)}] == [${ch}] => ${cc_res} ${quant}")
				}
				regex.ist_char_class_neg {
					cc_res := !re.check_char_class(pc, ch)
					println("[CC  ] i:${i} neg:true ${i}: [${re.get_char_class(level, pc)}] == [${ch}] => ${cc_res} ${quant}")
				}
				regex.ist_bsls_char {
					println("[BSLS] i:${i} [\\${tk.ch}] == [${ch}] => ${tk.validator(u8(ch))} ${quant}")
				}
				regex.ist_dot_char {
					println("[DOT ] i:$i [${ch}] ${quant}")
				}
				regex.ist_group_start {
					println("[ (  ] i:$i [${ch}] ${quant}")
				}
				regex.ist_group_end {
					println("[ )  ] i:$i [${ch}] ${quant}")
				}
				else {
					println("debug print level ${re.debug} ERROR!!")
				}
			}
		}

		// groups
		if tk.ist == regex.ist_group_start {
			println("ist_group_start")
			tk.group_start = i
			level = tk.row_i
			rep = 0
			pc++
			continue
		}
		else if tk.ist == regex.ist_group_end {
			println("ist_group_end ${tk.rep_min} ${tk.rep_max}")
			tk.group_end = i
			tk.rep++
			rep = tk.rep
			//re.prog[tk.jmp_pc].rep = tk.rep
			
			if tk.rep < tk.rep_min {
				println("Group under minimum")
				pc = tk.jmp_pc
				rep = 0
				continue
			}

			re.groups[level * 2] = re.prog[tk.jmp_pc].group_start
			re.groups[level * 2 + 1] = i

			if tk.rep < tk.rep_max {
				if re.prog[pc + 1].ist != regex.ist_prog_end {
					println("Check the rest")	
					mut tmp_buf := []int{len: re.prog.len}
					for c,x in re.prog {
						tmp_buf[c] = x.rep
					}
					s, e := re.match_base(in_txt, i, in_txt_len, level, pc + 1)					
					if s >= 0 {
						println("Good!!")
						return 0, e
					}
					for c,x in tmp_buf {
						re.prog[c].rep = x
					}
					
				}
				pc = tk.jmp_pc - 1
			}
			println("[ ) ] HERE WE ARE pc: ${pc} rep:${rep} min:${tk.rep_min} max:${tk.rep_max}")
			
		}

		// check rune alone
		else if tk.ist == regex.ist_simple_char {
			if tk.ch == ch {
				rep++
				tk.rep = rep
				i += char_len
				if rep < tk.rep_min {
					continue
				}
				if rep < tk.rep_max {
					continue
				}
			}
			// else { println("ist_simple_char FAILED") }
		}

		// char char class
		else if tk.ist == regex.ist_char_class_pos || tk.ist == regex.ist_char_class_neg {
			// if negative class set the negation flag
			mut cc_neg := false
			if tk.ist == regex.ist_char_class_neg {
				cc_neg = true
			}

			// check the CC
			mut cc_res := re.check_char_class(pc, ch)
			// invert the result if needed
			if cc_neg {
				cc_res = !cc_res
			}

			if cc_res {
				rep++
				tk.rep = rep
				i += char_len
				if rep < tk.rep_min {
					continue
				}
				if rep < tk.rep_max {
					if re.prog[pc + 1].ist != regex.ist_prog_end {
						mut tmp_buf := []int{len: re.prog.len}
						for c,x in re.prog {
							tmp_buf[c] = x.rep
						}
						s, e := re.match_base(in_txt, i, in_txt_len, level, pc + 1)
						if s >= 0 {
							return 0, e
						}
						for c,x in tmp_buf {
							re.prog[c].rep = x
						}
					}
					continue
				}
			}
			//else { println("ist_char_class FAILED") }
		}

		// check bsls
		else if tk.ist == regex.ist_bsls_char {
			if tk.validator(u8(ch)) == true {
				rep++
				i += char_len
				
				if rep < tk.rep_min {
					continue
				}
				//println("ist_bsls_char max check $rep < $tk.rep_max")
				if rep < tk.rep_max {
					if re.prog[pc + 1].ist != regex.ist_prog_end {
						println("Check the rest")
						mut tmp_buf := []int{len: re.prog.len}
						for c,x in re.prog {
							tmp_buf[c] = x.rep
						}
						s, e := re.match_base(in_txt, i, in_txt_len, level, pc + 1)
						if s >= 0 {
							return 0, e
						}
						for c,x in tmp_buf {
							re.prog[c].rep = x
						}
					}
					continue
				}
				//println("ist_bsls_char match!")
			} 
			//else { println("ist_bsls_char FAILED") }
			println("[BLSL] HERE WE ARE pc: ${pc} rep:${rep} min:${tk.rep_min} max:${tk.rep_max}")
			
		}

		// check dot metachar
		else if tk.ist == regex.ist_dot_char {
			//println("[DOT ] pc: ${level}:${pc} index:$i [${ch}] ${tk.rep} in {${tk.rep_min},${tk.rep_max}}")
			if tk.rep_min == 0 && rep == 0 && re.prog[pc].ist != regex.ist_prog_end {
				mut tmp_buf := []int{len: re.prog.len}
				for c,x in re.prog {
					tmp_buf[c] = x.rep
				}
				s, e := re.match_base(in_txt, i, in_txt_len, level, pc + 1) 
				if s >= 0 {
					return s, e
				}
				for c,x in tmp_buf {
					re.prog[c].rep = x
				}
			} 
			
			rep++
			i += char_len

			if rep < tk.rep_min {
				continue
			}
			
			if rep < tk.rep_max {			
				if re.prog[pc + 1].ist != regex.ist_prog_end {
					mut tmp_buf := []int{len: re.prog.len}
					for c,x in re.prog {
						tmp_buf[c] = x.rep
					}
					s, e := re.match_base(in_txt, i, in_txt_len, level, pc + 1) 
					if s >= 0 {
						return s, e
					}
					for c,x in tmp_buf {
						re.prog[c].rep = x
					}
				}
				continue
			}
		}
	
		else {
			eprintln("regex runtime ERROR!!")
			re.call_level--
			return regex.err_internal_error, -1
		}

		//======================================
		// Quantifier management
		//======================================
		println("QM $rep of {${tk.rep_min},${tk.rep_max}}")
		if rep >= tk.rep_min && rep <= tk.rep_max {
			pc++
			// managing escaped OR
			if pc > 0 && re.prog[pc-1].or_flag == true {
				pc++
			}
			rep = 0
			continue
		}

		// check if we have an OR token to use
		if tk.or_flag == true {
			pc++
			rep = 0
			continue
		}

		if re.debug > 2 {
			println("lvl: ${re.call_level:2} pc: ${level:2}:${pc:3}/${re.prog.len - 1:3} NO MATCH")
		}

		re.call_level--
		return regex.no_match_found, -1
	}

	re.call_level--
	println("ENDING: ${i} of ${in_txt_len} PC:$pc of ${re.prog.len - 1}")

	
	// Normal program end
	if re.prog[pc].ist == regex.ist_prog_end {
		println("END ist_prog_end")		
		re.groups[0] = 0
		re.groups[1] = i
		return 0, i
	}

	// we are in the last token loop and the text run out
	if i >= in_txt_len && (
		re.prog[pc + 1].ist == regex.ist_prog_end ||
		(pc+2 < re.prog.len && re.prog[pc + 1].ist == regex.ist_group_end && re.prog[pc + 2].ist == regex.ist_prog_end)

	){
		println("HERE END without text!")
		println("END pc:${pc} rep:${rep} of {${tk.rep_min},${tk.rep_max}}")
		println("END last token loop level:${level}")
		
		if re.prog[pc + 1].ist == regex.ist_group_end &&
			re.prog[pc + 1].rep >= re.prog[pc + 1].rep_min && 
			re.prog[pc + 1].rep <= re.prog[pc + 1].rep_max {
				re.groups[0] = 0
				re.groups[1] = i
				return 0,i
		} else if re.prog[pc + 1].ist == regex.ist_prog_end &&
			re.prog[pc].rep >= re.prog[pc].rep_min && 
			re.prog[pc].rep <= re.prog[pc].rep_max {
				re.groups[0] = 0
				re.groups[1] = i
				return 0,i
		}
		
	}


	// check if last instructions can match without text leftovers!
/*
	if i >= in_txt_len {
		println("END text run out")
		mut tmp_pc := pc + 1
		for re.prog[tmp_pc].ist != regex.ist_prog_end{
			if re.prog[tmp_pc].rep_min > 0 {
				return regex.no_match_found, -1
			}
			tmp_pc++
		}
		return 0, i
	}
*/

	return regex.no_match_found, -1
}

pub fn (mut re RE) match_string(in_txt string, in_i int) (int, int) {
	re.call_level = -1
	mut s, e := re.match_base(in_txt.str, in_i, in_txt.len, 0, 0)

	if s == regex.program_end_ok { s = 0 }

	if s >= 0 {
		// check ^ flag
		if ((re.flag & regex.f_ms) != 0) && (s > 0) {
			return regex.no_match_found, -1
		}
		// check $ flag
		if ((re.flag & regex.f_me) != 0) && (e != in_txt.len) {
			return regex.no_match_found, -1
		}
	}
	return s, e
}