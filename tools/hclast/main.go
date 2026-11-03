// Command hclast prints OpenTofu configuration (a module directory, or one
// .tf or .tfvars file) as JSON,
// parsed by HashiCorp's HCL library: for every attribute its source text,
// its literal value when it has one, and the references it makes.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	ctyjson "github.com/zclconf/go-cty/cty/json"
)

type Value struct {
	Source  string          `json:"source"`
	Literal json.RawMessage `json:"literal,omitempty"`
	Refs    []string        `json:"refs"`
	Kind    string          `json:"kind"`
	Items   []Value         `json:"items,omitempty"`
	Fields  []Field         `json:"fields,omitempty"`
}

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
