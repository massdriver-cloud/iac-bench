// Command hclast prints OpenTofu configuration (a module directory, or one
// .tf or .tfvars file) as JSON,
// parsed by HashiCorp's HCL library: for every attribute its source text,
// its literal value when it has one, the references it makes, and its
// expression tree.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/zclconf/go-cty/cty"
	ctyjson "github.com/zclconf/go-cty/cty/json"
)

type Value struct {
	Source  string          `json:"source"`
	Literal json.RawMessage `json:"literal,omitempty"`
	Refs    []string        `json:"refs"`
	Kind    string          `json:"kind"`
	Items   []Value         `json:"items,omitempty"`
	Fields  []Field         `json:"fields,omitempty"`
	Expr    Node            `json:"expr"`
}

// Node is one expression-tree node: "t" names its kind, the other keys its
// operands. Kinds the tree does not model are {"t": "unknown"}.
type Node map[string]any

type Field struct {
	Key   string `json:"key"`
	Value Value  `json:"value"`
}

type Attr struct {
	Value
	Line int `json:"line"`
}

type Block struct {
	Type   string   `json:"type"`
	Labels []string `json:"labels"`
	Line   int      `json:"line"`
	Body   *Body    `json:"body"`
}

type Body struct {
	Attributes map[string]Attr `json:"attributes"`
	Blocks     []Block         `json:"blocks"`
}

type File struct {
	Error string `json:"error,omitempty"`
	Body  *Body  `json:"body,omitempty"`
}

func refs(expr hcl.Expression) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, t := range expr.Variables() {
		name := t.RootName()
		if len(t) > 1 {
			if a, ok := t[1].(hcl.TraverseAttr); ok {
				name += "." + a.Name
			}
		}
		seen[name] = true
	}
	for k := range seen {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func literal(expr hclsyntax.Expression) json.RawMessage {
	if len(expr.Variables()) > 0 || hasCall(expr) {
		return nil
	}
	v, diags := expr.Value(nil)
	if diags.HasErrors() || !v.IsWhollyKnown() {
		return nil
	}
	b, err := ctyjson.Marshal(v, v.Type())
	if err != nil {
		return nil
	}
	return b
}

func hasCall(expr hclsyntax.Expression) bool {
	found := false
	hclsyntax.VisitAll(expr, func(n hclsyntax.Node) hcl.Diagnostics {
		if _, ok := n.(*hclsyntax.FunctionCallExpr); ok {
			found = true
		}
		return nil
	})
	return found
}

func kind(expr hclsyntax.Expression) string {
	switch expr.(type) {
	case *hclsyntax.TemplateExpr:
		return "template"
	case *hclsyntax.TemplateWrapExpr:
		return "template_wrap"
	case *hclsyntax.ScopeTraversalExpr:
		return "reference"
	case *hclsyntax.ConditionalExpr:
		return "conditional"
	case *hclsyntax.FunctionCallExpr:
		return "call"
	case *hclsyntax.ForExpr:
		return "for"
	case *hclsyntax.ObjectConsExpr:
		return "object"
	case *hclsyntax.TupleConsExpr:
		return "tuple"
	case *hclsyntax.LiteralValueExpr:
		return "literal"
	}
	return "expression"
}

func value(src []byte, expr hclsyntax.Expression) Value {
	v := Value{
		Source:  withoutComments(expr.Range().SliceBytes(src)),
		Literal: literal(expr),
		Refs:    refs(expr),
		Kind:    kind(expr),
		Expr:    tree(expr),
	}
	switch e := expr.(type) {
	case *hclsyntax.TupleConsExpr:
		for _, item := range e.Exprs {
			v.Items = append(v.Items, value(src, item))
		}
	case *hclsyntax.ObjectConsExpr:
		for _, item := range e.Items {
			v.Fields = append(v.Fields, Field{Key: key(src, item.KeyExpr), Value: value(src, item.ValueExpr)})
		}
	}
	return v
}

var binaryOps = map[*hclsyntax.Operation]string{
	hclsyntax.OpLogicalOr: "||", hclsyntax.OpLogicalAnd: "&&",
	hclsyntax.OpEqual: "==", hclsyntax.OpNotEqual: "!=",
	hclsyntax.OpGreaterThan: ">", hclsyntax.OpGreaterThanOrEqual: ">=",
	hclsyntax.OpLessThan: "<", hclsyntax.OpLessThanOrEqual: "<=",
	hclsyntax.OpAdd: "+", hclsyntax.OpSubtract: "-", hclsyntax.OpMultiply: "*",
	hclsyntax.OpDivide: "/", hclsyntax.OpModulo: "%",
}

func ctyNode(v cty.Value) Node {
	if !v.IsWhollyKnown() {
		return Node{"t": "unknown"}
	}
	b, err := ctyjson.Marshal(v, v.Type())
	if err != nil {
		return Node{"t": "unknown"}
	}
	return Node{"t": "lit", "v": json.RawMessage(b)}
}

func steps(trav hcl.Traversal) []Node {
	out := []Node{}
	for _, step := range trav {
		switch s := step.(type) {
		case hcl.TraverseRoot:
			out = append(out, Node{"attr": s.Name})
		case hcl.TraverseAttr:
			out = append(out, Node{"attr": s.Name})
		case hcl.TraverseIndex:
			out = append(out, Node{"index": ctyNode(s.Key)})
		case hcl.TraverseSplat:
			out = append(out, Node{"splat": true})
		}
	}
	return out
}

func trees(exprs []hclsyntax.Expression) []Node {
	out := []Node{}
	for _, e := range exprs {
		out = append(out, tree(e))
	}
	return out
}

// tree is the expression as nested nodes: enough to evaluate conditions
// over input values without OpenTofu.
func tree(expr hclsyntax.Expression) Node {
	switch e := expr.(type) {
	case *hclsyntax.LiteralValueExpr:
		return ctyNode(e.Val)
	case *hclsyntax.ScopeTraversalExpr:
		return Node{"t": "ref", "steps": steps(e.Traversal)}
	case *hclsyntax.RelativeTraversalExpr:
		return Node{"t": "rel", "src": tree(e.Source), "steps": steps(e.Traversal)}
	case *hclsyntax.IndexExpr:
		return Node{"t": "index", "coll": tree(e.Collection), "key": tree(e.Key)}
	case *hclsyntax.TemplateExpr:
		if lit := literal(e); lit != nil {
			return Node{"t": "lit", "v": lit}
		}
		return Node{"t": "template", "parts": trees(e.Parts)}
	case *hclsyntax.TemplateWrapExpr:
		return tree(e.Wrapped)
	case *hclsyntax.ParenthesesExpr:
		return tree(e.Expression)
	case *hclsyntax.BinaryOpExpr:
		if op, ok := binaryOps[e.Op]; ok {
			return Node{"t": "binary", "op": op, "l": tree(e.LHS), "r": tree(e.RHS)}
		}
	case *hclsyntax.UnaryOpExpr:
		op := "-"
		if e.Op == hclsyntax.OpLogicalNot {
			op = "!"
		}
		return Node{"t": "unary", "op": op, "x": tree(e.Val)}
	case *hclsyntax.ConditionalExpr:
		return Node{"t": "cond", "if": tree(e.Condition), "then": tree(e.TrueResult), "else": tree(e.FalseResult)}
	case *hclsyntax.FunctionCallExpr:
		return Node{"t": "call", "name": e.Name, "args": trees(e.Args), "expand": e.ExpandFinal}
	case *hclsyntax.TupleConsExpr:
		return Node{"t": "tuple", "items": trees(e.Exprs)}
	case *hclsyntax.ObjectConsExpr:
		items := []Node{}
		for _, item := range e.Items {
			items = append(items, Node{"k": keyTree(item.KeyExpr), "v": tree(item.ValueExpr)})
		}
		return Node{"t": "object", "items": items}
	case *hclsyntax.ForExpr:
		n := Node{"t": "for", "kvar": e.KeyVar, "vvar": e.ValVar, "coll": tree(e.CollExpr), "val": tree(e.ValExpr), "group": e.Group}
		if e.KeyExpr != nil {
			n["key"] = tree(e.KeyExpr)
		}
		if e.CondExpr != nil {
			n["cond"] = tree(e.CondExpr)
		}
		return n
	case *hclsyntax.SplatExpr:
		return Node{"t": "splat", "src": tree(e.Source), "each": tree(e.Each)}
	case *hclsyntax.AnonSymbolExpr:
		return Node{"t": "anon"}
	}
	return Node{"t": "unknown"}
}

// keyTree reads an object key: a bare keyword is its own name, as OpenTofu
// reads it, unless parenthesized.
func keyTree(expr hclsyntax.Expression) Node {
	if k, ok := expr.(*hclsyntax.ObjectConsKeyExpr); ok {
		if name := hcl.ExprAsKeyword(k.Wrapped); name != "" && !k.ForceNonLiteral {
			b, _ := json.Marshal(name)
			return Node{"t": "lit", "v": json.RawMessage(b)}
		}
		return tree(k.Wrapped)
	}
	return tree(expr)
}

// withoutComments blanks comment tokens, keeping line structure, so a
// comment that mentions var.x can never read as a reference.
func withoutComments(b []byte) string {
	out := append([]byte(nil), b...)
	tokens, _ := hclsyntax.LexExpression(b, "", hcl.Pos{Line: 1, Column: 1, Byte: 0})
	for _, tok := range tokens {
		if tok.Type != hclsyntax.TokenComment {
			continue
		}
		for i := tok.Range.Start.Byte; i < tok.Range.End.Byte && i < len(out); i++ {
			if out[i] != '\n' {
				out[i] = ' '
			}
		}
	}
	return string(out)
}

func key(src []byte, expr hclsyntax.Expression) string {
	if k, ok := expr.(*hclsyntax.ObjectConsKeyExpr); ok {
		if name := hcl.ExprAsKeyword(k.Wrapped); name != "" && !k.ForceNonLiteral {
			return name
		}
		if lit := literal(k.Wrapped); lit != nil {
			var s string
			if json.Unmarshal(lit, &s) == nil {
				return s
			}
		}
	}
	return string(expr.Range().SliceBytes(src))
}

func body(src []byte, b *hclsyntax.Body) *Body {
	out := &Body{Attributes: map[string]Attr{}, Blocks: []Block{}}
	for name, a := range b.Attributes {
		out.Attributes[name] = Attr{Value: value(src, a.Expr), Line: a.SrcRange.Start.Line}
	}
	for _, blk := range b.Blocks {
		labels := blk.Labels
		if labels == nil {
			labels = []string{}
		}
		out.Blocks = append(out.Blocks, Block{
			Type: blk.Type, Labels: labels, Line: blk.TypeRange.Start.Line, Body: body(src, blk.Body),
		})
	}
	return out
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: hclast <module-dir | file.tf | file.tfvars>")
		os.Exit(2)
	}
	paths := []string{os.Args[1]}
	if info, err := os.Stat(os.Args[1]); err == nil && info.IsDir() {
		paths, _ = filepath.Glob(filepath.Join(os.Args[1], "*.tf"))
		sort.Strings(paths)
	}
	files := map[string]File{}
	for _, p := range paths {
		src, err := os.ReadFile(p)
		if err != nil {
			files[filepath.Base(p)] = File{Error: err.Error()}
			continue
		}
		f, diags := hclsyntax.ParseConfig(src, filepath.Base(p), hcl.Pos{Line: 1, Column: 1})
		if diags.HasErrors() {
			files[filepath.Base(p)] = File{Error: diags.Error()}
			continue
		}
		files[filepath.Base(p)] = File{Body: body(src, f.Body.(*hclsyntax.Body))}
	}
	enc := json.NewEncoder(os.Stdout)
	if err := enc.Encode(map[string]any{"files": files}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
