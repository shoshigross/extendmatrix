require 'rational'
require 'matrix'
require 'mapcar'

class Vector
	include Enumerable
	module Norm 
		def Norm.sqnorm(obj, p)
      sum = 0
      obj.each{|x| sum += x ** p}
      sum
    end 
	end

	alias :length :size
	alias :index :[]
	def [](i)
		case i
		when Range
			Vector[*to_a.slice(i)]
		else
			index(i)
		end	
	end

	def []=(i, v)
		case i
		when Range
			#i.each{|e| self[e] = v[e - i.begin]}
			(self.size..i.begin - 1).each{|e| self[e] = 0} # self.size must be in the first place because the size of self can be modified 
			[v.size, i.entries.size].min.times {|e| self[e + i.begin] = v[e]}
			(v.size + i.begin .. i.end).each {|e| self[e] = 0}
		else
			@elements[i]=v 
		end
	end

	class << self
		def concat(*args)
			v = []
			args.each{|x| v += x.to_a}
			Vector[*v]
		end
	end

	def collect! 
		els = @elements.collect! {|v| yield(v)}
		Vector.elements(els, false)
	end

	def each 
		(0...size).each {|i| yield(self[i])}
		nil
	end

	def max
		to_a.max
	end
  
  def min
    to_a.min
  end

	def norm(p = 2)
    Norm.sqnorm(self, p) ** (Float(1)/p)
  end

  
  def norm_inf
    [min.abs, max.abs].max
  end
	
	def slice(*args)
		Vector[*to_a.slice(*args)]	
	end

	def slice_set(v, b, e)
		for i in b..e
			self[i] = v[i-b]	
		end
	end
	
	def slice=(args)
		case args[1]
		when Range
			slice_set(args[0], args[1].begin, args[1].last)
		else
			slice_set(args[0], args[1], args[2])
		end
	end

	def /(c)
		map {|e| e.quo(c)}
	end

	def transpose
		Matrix[self.to_a]
	end
	
	alias :t :transpose
	
	# Computes the Householder vector (MC, Golub, p. 210, algorithm 5.1.1)
	def house
		s = self[1..length-1]
		sigma = s.inner_product(s)
		v = clone; v[0] = 1
		if sigma == 0
			beta = 0
		else
			mu = Math.sqrt(self[0] ** 2 + sigma)
			if self[0] <= 0
				v[0] = self[0] - mu
			else
				v[0] = - sigma.quo(self[0] + mu)
			end
			v2 = v[0] ** 2
			beta = 2 * v2.quo(sigma + v2)
			v /= v[0]
		end
		return v, beta
	end

	# Projection operator (http://en.wikipedia.org/wiki/Gram-Schmidt_process#The_Gram.E2.80.93Schmidt_process)
	def proj(v)
		vp = v.inner_product(self)
		vp = Float vp if vp.is_a?(Integer)
		self * (vp / inner_product(self))
	end

	def normalize
		self / self.norm
	end

	# Stabilized Gram-Schmidt process (http://en.wikipedia.org/wiki/Gram-Schmidt_process#Algorithm)
	def Vector.gram_schmidt(*vectors)
		v = vectors.clone
		for j in 0...v.size
			for i in 0..j-1
				v[j] -= v[i] * v[j].inner_product(v[i])
			end
			v[j] /= v[j].norm
		end
		v
	end
end

class Matrix
	include Enumerable
	public_class_method :new

  attr_reader :rows, :wrap
	@wrap = nil
	
	def initialize(*argv)
		return initialize_old(*argv) if argv[0].is_a?(Symbol)
		n, m, val = argv; val = 0 if not val
		f = (block_given?)? lambda {|i,j| yield(i, j)} : lambda {|i,j| val}
		init_rows((0...n).collect {|i| (0...m).collect {|j| f.call(i,j)}}, true)
	end
	
	def initialize_old(init_method, *argv)
		self.funcall(init_method, *argv) # in Ruby1.9
		#self.send(init_method, *argv) # in Ruby1.8
	end

	alias :ids :[]
	def [](i, j)
		case i
		when Range 
			case j
			when Range
				Matrix[*i.collect{|l| self.row(l)[j].to_a}]
			else
				column(j)[i]	
			end
		else
			case j
			when Range
				row(i)[j]
			else
				ids(i, j)
			end
		end		
	end

	def []=(i, j, v)
		case i
		when Range
			if i.entries.size == 1
				self[i.begin, j] = (v.is_a?(Matrix) ? v.row(0) : v)
			else
				case j
				when Range
					if j.entries.size == 1
						self[i, j.begin] = (v.is_a?(Matrix) ? v.column(0) : v)
					else
						i.each{|l| self.row= l, v.row(l - i.begin), j}
					end
				else
					self.column= j, v, i	
				end
			end
		else
			case j
			when Range
				if j.entries.size == 1
					self[i, j.begin] = (v.is_a?(Vector) ? v[0] : v)
				else
					self.row= i, v, j
				end
			else
				@rows[i][j] = (v.is_a?(Vector) ? v[0] : v)

			end
		end		
	end	

	def clone
		super
	end

	def initialize_copy(orig)
		init_rows(orig.rows, true)
		self.wrap=(orig.wrap)
	end


	class << self
		def diag(*args)
			dsize = 0
			sizes = args.collect{|e| x = (e.is_a?(Matrix)) ? e.row_size : 1; dsize += x; x}
			m = Matrix.zero(dsize)
			count = 0

			sizes.size.times{|i| 
				range = count..(count+sizes[i]-1)
				m[range, range] = args[i]
				count += sizes[i]
			}
			m
		end

	end

	# Division by a scalar
	def quo(v)
		map {|e| e.quo(v)}
	end

	# quo seems always desirable
	alias :/ :quo

	def set(m)
		0.upto(m.row_size - 1) do |i|
			0.upto(m.column_size - 1) do |j|
				self[i, j] = m[i, j]
			end
		end
		self.wrap = m.wrap
	end

	def wraplate(ijwrap = "")
		 "class << self
			  def [](i, j)
			    #{ijwrap}; @rows[i][j]
		    end

		    def []=(i, j, v)
		      #{ijwrap}; @rows[i][j] = v
		    end
		  end"
	end
	
	def wrap=(mode = :torus)
		case mode
		when :torus then eval(wraplate("i %= row_size; j %= column_size"))
		when :h_cylinder then eval(wraplate("i %= row_size"))
		when :v_cylinder then eval(wraplate("j %= column_size"))
		when :nil then eval(wraplate)
		end
		@wrap = mode
	end
	
	def max_len_column(j)		
		column_collect(j) {|x| x.to_s.length}.max
	end
	
	def cols_len
		(0...column_size).collect {|j| max_len_column(j)}
	end
	
	def to_s(mode = :pretty, len_col = 3)
		return super if empty?
		if mode == :pretty
			clen = cols_len
			to_a.collect {|r| mapcar(r, clen) {|x, l| format("%#{l}s ",x.to_s)} << "\n"}.join("")
		else
			i = 0; s = ""; cs = column_size
			each do |e|
				i = (i + 1) % cs
				s += format("%#{len_col}s ", e.to_s)
				s += "\n" if i == 0
			end
			s
		end
	end

	def each
		@rows.each {|x| x.each {|e| yield(e)}}
		nil
	end

	  
	module MMatrix
		def MMatrix.default_block(block)
    	block ? lambda { |i| block.call(i) } : lambda {|i| i }
  	end

		#
		# Returns: 
		# 1) the index of row/column and 
		# 2) the values Vector for changing the row/column and 
		# 3) the range of changes
		#
		def MMatrix.id_vect_range(args, l)
			i = args[0] # the column(/the row) to be change
			vect = args[1] # the values vector
			
		  case args.size
				when 3 then range = args[2] # the range of the elements to be change
				when 4 then range = args[2]..args[3] #the range by borders
				else range = 0...l
			end
			return i, vect, range
		end
		
		#
		# Returns the matrix of rows/columns indicated in 'range'
		#
		def MMatrix.rc2matrix(mat, direction, range)
			a = mat.send(direction, range).to_a
			Matrix[*a] 
		end
	end

	#
	# Returns an array with the elements collected from the row "i". 
	# When a block is given, the elements of that vector are iterated.
	#
	def row_collect(i, &block)
		f = MMatrix.default_block(block)
		@rows[i].collect {|e| f.call(e)}
	end

	#
	# Returns row vector number "i" like Matrix.row as a Vector.
	# When the block is given, the elements of row "i" are mmodified
	#
	def row!(i)
		if block_given?
			@rows[i].collect! {|e| yield e }
		else
			Vector.elements(@rows[i], false)
		end
	end
	alias :row_collect! :row!

	#
	# Returns an array with the elements collected from the column "j". 
	# When a block is given, the elements of that vector are iterated.
	#
	def column_collect(j, &block)
		f = MMatrix.default_block(block)	
		(0...row_size).collect {|r| f.call(self[r, j])}
	end
	
	#
	# Returns column vector number "j" as a Vector.
	# When the block is given, the elements of column "j" are mmodified
	#
	def column!(j)
		if block_given?
			(0...row_size).collect { |i| @rows[i][j] = yield @rows[i][j] }
		else
			column(j)
		end
	end
	alias :column_collect! :column!

	#
	# Set a certain column with the values of a Vector
  # m = Matrix.new(3, 3){|i, j| i * 3 + j + 1}
  # m.column= 1, Vector[1, 1, 1], 1..2
  # m => 1 2 3
  #      4 1 6
  #      7 1 9  
	#
	def column=(args)
		m = row_size
		c, v, r = MMatrix.id_vect_range(args, m)
		(m..r.begin - 1).each{|i| self[i, c] = 0}
		[v.size, r.entries.size].min.times{|i| self[i + r.begin, c] = v[i]}
		((v.size + r.begin)..r.entries.last).each {|i| self[i, c] = 0}
	end
	
	def row=(args)
		i, val, range = MMatrix.id_vect_range(args, column_size) 	
		row!(i)[range] = val
	end

	def norm(p = 2)
    Vector::Norm.sqnorm(self, p) ** (Float(1)/p)
	end
	
	def norm_frobenius
		norm
	end
	alias :normF :norm_frobenius

	def empty?
		@rows.empty? if @rows
	end

	# Returns the row/s of matrix as a Matrix 
	def row2matrix(r) 
		MMatrix.rc2matrix(self, :row, r)
	end

	# Returns the colomn/s of matrix as a Matrix
	def column2matrix(c) 
		MMatrix.rc2matrix(self, :column, c).t
	end
		
	def equal_in_delta?(mat, delta = 1.0e-10)
		delta = delta.abs
		mapcar(self, mat){|x, y| return false if (x < y - delta or x > y + delta)  }
		true
	end

  module LU
    def LU.tau(m, k) 
      t = m.column2matrix(k)
      tk = t[k, 0]
      (0..k).each{|i| t[i, 0] = 0}
      return t if tk == 0
      (k+1...m.row_size).each{|i| t[i, 0] = t[i, 0].to_f / tk}
      t
    end

    def LU.M(m, k)
      i = Matrix.I(m.row_size)
      t = tau(m, k)
      e = i.row2matrix(k)
      i - t * e
    end

    def LU.gauss(m)
      a = m.clone
      (0..m.column_size-2).collect {|i| mi = M(a, i); a = mi * a; mi }
    end
  end 
  
	def U
		u = self.clone
		LU.gauss(self).each{|m| u = m * u}
		u
	end

	def L
		trans = LU.gauss(self)
		l = trans[0].inv
		(1...trans.size).each{|i| p trans[i].inv; l *= trans[i].inv}
		l
	end

	module House
		def House.QR(mat) #Householder QR
			h = []
			a = mat.clone
			m = a.row_size
			n = a.column_size
			n.times{|j|
				v, beta = a[j..m - 1, j].house

				h[j] = Matrix.diag(Matrix.I(j), Matrix.I(m-j)- beta * (v * v.t))
			
				a[j..m-1, j..n-1] = (Matrix.I(m-j) - beta * (v * v.t)) * a[j..m-1, j..n-1]
				a[(j+1)..m-1,j] = v[2..(m-j)] if j < m - 1 }
			h
		end

		def House.UV(essential, dim, beta)
			v = Vector.concat(Vector[1], essential)
			dimv = v.size
			Matrix.diag(Matrix.I(dim - dimv), Matrix.I(dimv) - beta * (v * v.t) )
		end

		def House.bidiag(mat) #Householder Bidiagonalization
			a = mat.clone
			m = a.row_size
			n = a.column_size
			ub = Matrix.I(m)
			vb = Matrix.I(n)
			n.times{|j|
				v, beta = a[j..m-1,j].house
				a[j..m-1, j..n-1] = (Matrix.I(m-j) - beta * (v * v.t)) * a[j..m-1, j..n-1]
				a[j+1..m-1, j] = v[1..(m-j-1)]
				ub *= UV(a[j+1..m-1,j], m, beta) #Ub = U_1 * U_2 * ... * U_n
				if j < n - 2
					v, beta = (a[j, j+1..n-1]).house
					a[j..m-1, j+1..n-1] = a[j..m-1, j+1..n-1] * (Matrix.I(n-j-1) - beta * (v * v.t))
					a[j, j+2..n-1] = v[1..n-j-2]
					vb  *= UV(a[j, j+2..n-1], n, beta) #Vb = V_1 * U_2 * ... * V_n-2	
				end	}
			return ub, vb
		end
	end #end of Householder module

	# the bidiagonal matrix obtained with Householder Bidiagonalization algorithm
	def bidiagonal 
		ub, vb = House.bidiag(self)
		ub.t * self * vb
	end

	#householder Q = H_1 * H_2 * H_3 * ... * H_n
	def houseQ 
		h = House.QR(self)
    q = h[0] 
    (1...h.size).each{|i| q *= h[i]} 
    q
  end

  # R = H_n * H_n-1 * ... * H_1 * A
  def houseR
    h = House.QR(self)
    r = self.clone
    h.size.times{|i| r = h[i] * r}
    r
  end

	# Modified Gram Schmidt QR factorization (MC, Golub, p. 232)
	def gram_schmidt
		r = clone
		q = clone
		n = column_size
		m = row_size
		for k in 0...n
			r[k,k] = self[0...m, k].norm
			q[0...m, k] = self[0...m, k] / r[k, k]
			for j in (k+1)...n
				r[k, j] = q[0...m, k].t * self[0...m, j]
				self[0...m, j] -= q[0...m, k] * r[k, j]
			end
		end
	end

	module Givens
		def Givens.givens(a, b)
			if b == 0 
				c = 0; s = 0
			else
				if b.abs > a.abs
					tau = Float(-a)/b; s = 1/Math.sqrt(1+tau**2); c = s * tau
				else
					tau = Float(-b)/a; c = 1/Math.sqrt(1+tau**2); s = c * tau
				end
			end
			return c, s
		end
	
		# Computes the upper triangular matrix R and the orthogonal matrix Q
		# where Q^t A = R (MC, Golub, algorithm 5.2.2)
		def Givens.QR(mat)
			r = mat.clone
			m = r.row_size
			n = r.column_size
			q = Matrix.I(m)
			n.times{|j|
				m-1.downto(j+1){|i|
					c, s = givens(r[i - 1, j], r[i, j])
					qt = Matrix.I(m); qt[i-1..i, i-1..i] = Matrix[[c, s],[-s, c]]
					q *= qt
					r[i-1..i, j..n-1] = Matrix[[c, -s],[s, c]] * r[i-1..i, j..n-1]}}
			return r, q
		end

		def Givens.R(mat)
			QR(mat)[0]
		end

		def Givens.Q(mat)
			QR(mat)[1]
		end
	end

	def givensR
		Givens.QR(self)[0]
	end

	def givensQ
		Givens.QR(self)[1]
	end

	module Hessenberg
		#the matrix must be an upper Hessenberg matrix
		def Hessenberg.QR(mat)
			r = mat.clone
			n = row_size
			q = Matrix.I(n)
			for j in (0...n-1)
				c, s = givens(r[j,j], r[j+1, j])
				cs = Matrix[[c, s], [-s, c]]
				q *= Matrix.diag(Matrix.I(j), cs, Matrix.I(n - j - 2))
				r[j..j+1, j..n-1] = cs.t * r[j..j+1, j..n-1] 
			end
			return q, r
		end

		def Hessenberg.Q(mat)
			QR(mat)[0]
		end

		def Hessenberg.R(mat)
			QR(mat)[1]
		end
	end

	def hessenbergQ
		Hessenberg.QR(self)[0]	
	end
	
	def hessenbergR
		Hessenberg.QR(self)[1]	
	end

	#Householder Reduction to Hessenberg Form
	def hessenberg
		h = self.clone
		n = row_size
		u0 = Matrix.I(n)
		for k in (0...n - 2)
			v, beta = h[k+1..n-1, k].house #the householder matrice part
			houseV = Matrix.I(n-k-1) - beta * (v * v.t) 
			u0 *= Matrix.diag(Matrix.I(k+1), houseV)
			h[k+1..n-1, k..n-1] = houseV * h[k+1..n-1, k..n-1]
			h[0..n-1, k+1..n-1] = h[0..n-1, k+1..n-1] * houseV
		end
		return h, u0
	end

	def hessenbergU0
		hessenberg[1]
	end
	
	def diagTol(m1, m0, eps)
		m1.row_size.times{|i|
			return false if (m1[i,i]-m0[i,i]).abs > eps
		}
		true
	end

	def eigenvalQR(eps = 1.0e-10, steps = 100)
		h = self.hessenberg[0]
		h1 = Matrix[]
		i = 0
		loop do
			h1 = h.houseR * h.houseQ	
			break if diagTol(h1, h, eps) or steps <= 0
			h = h1.clone 
			steps -= 1
			i += 1
		end
		h1
	end

	module Jacobi
		def Jacobi.off(a)
			n = a.row_size
			sum = 0
			n.times{|i| n.times{|j| sum += a[i, j]**2 if j != i}}
			Math.sqrt(sum)
		end

		def Jacobi.max(a)
			n = a.row_size
			max = 0
			p = 0
			q = 0
			n.times{|i|
				((i+1)...n).each{|j| 
					val = a[i, j].abs
					if val > max
						max = val
						p = i
						q = j
					end	}}
			return p, q
		end

		def Jacobi.sym_schur2(a, p, q)
			if a[p, q] != 0
				tau = Float(a[q, q] - a[p, p])/(2 * a[p, q])
				if tau >= 0
					t = 1./(tau + Math.sqrt(1 + tau ** 2))
				else	
					t = -1./(-tau + Math.sqrt(1 + tau ** 2))
				end
				c = 1./Math.sqrt(1 + t ** 2)
				s = t * c
			else
				c = 1
				s = 0
			end
			return c, s
		end

		def Jacobi.J(p, q, c, s, n)
			j = Matrix.I(n)
			j[p,p] = c; j[p, q] = s
			j[q,p] = -s; j[q, q] = c
			j
		end
	end

	# Classical Jacobi 8.4.3 Golub & van Loan
	def cJacobi(tol = 1.0e-10)
		a = self.clone
		n = row_size
		v = Matrix.I(n)
		eps = tol * a.normF
		while Jacobi.off(a) > eps
			print "\neps:#{eps} off:#{Jacobi.off(a)}\n"
			print a
			p, q = Jacobi.max(a)
			c, s = Jacobi.sym_schur2(a, p, q)
			print "\np:#{p} q:#{q} c:#{c} s:#{s}\n"
			j = Jacobi.J(p, q, c, s, n)
			a = j.t * a * j
			v = v * j
		end
		return a, v
	end
end
